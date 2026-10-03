import XCTest
@testable import UtterRuntime

@MainActor
final class PluginRuntimeTests: XCTestCase {
    private let number = ServiceKey<Int>("number")

    func testDependenciesActivateBeforeConsumersAndStopInReverseOrder() async throws {
        var trace: [String] = []
        let provider = PluginRegistration(
            descriptor: PluginDescriptor(id: "z.provider", provides: [number.reference])
        ) { context, _ in
            trace.append("provider")
            try context.provide(self.number, value: 42)
            try context.scope.onDispose { trace.append("stop-provider") }
        }
        let consumer = PluginRegistration(
            descriptor: PluginDescriptor(id: "a.consumer", requires: [number.required])
        ) { context, _ in
            XCTAssertEqual(try context.require(self.number), 42)
            trace.append("consumer")
            try context.scope.onDispose { trace.append("stop-consumer") }
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([consumer, provider]))
        try await runtime.start([PluginSelection("a.consumer"), PluginSelection("z.provider")])
        XCTAssertEqual(trace, ["provider", "consumer"])
        XCTAssertEqual(try runtime.service(number), 42)
        try await runtime.stop()
        try await runtime.stop()
        XCTAssertEqual(trace, ["provider", "consumer", "stop-consumer", "stop-provider"])
        XCTAssertThrowsError(try runtime.service(number))
    }

    func testInvalidGraphsNeverCallFactories() async throws {
        var calls = 0
        let registration = PluginRegistration(
            descriptor: PluginDescriptor(id: "consumer", requires: [number.required])
        ) { _, _ in calls += 1 }
        let runtime = PluginRuntime(catalog: try PluginCatalog([registration]))
        do {
            try await runtime.start([PluginSelection("consumer")])
            XCTFail("Missing dependency was accepted")
        } catch {
            XCTAssertEqual(error as? PluginRuntimeError, .missingService(plugin: "consumer", service: "number"))
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(runtime.state, .stopped)
    }

    func testFailedActivationDisposesPartialScopeBeforeDependencies() async throws {
        enum Failure: Error { case injected }
        var trace: [String] = []
        let provider = PluginRegistration(
            descriptor: PluginDescriptor(id: "provider", provides: [number.reference])
        ) { context, _ in
            try context.provide(self.number, value: 1)
            try context.scope.onDispose { trace.append("provider") }
        }
        let failing = PluginRegistration(
            descriptor: PluginDescriptor(id: "failing", requires: [number.required])
        ) { context, _ in
            try context.scope.onDispose { trace.append("first") }
            try context.scope.onDispose { trace.append("second") }
            throw Failure.injected
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([provider, failing]))
        do {
            try await runtime.start([PluginSelection("failing"), PluginSelection("provider")])
            XCTFail("Activation unexpectedly succeeded")
        } catch {}
        XCTAssertEqual(trace, ["second", "first", "provider"])
        XCTAssertEqual(runtime.state, .failed)
        XCTAssertThrowsError(try runtime.service(number))
    }

    func testUndeclaredLookupAndRegistrationFail() async throws {
        var context: PluginContext?
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "empty")) { value, _ in
            context = value
            XCTAssertThrowsError(try value.require(self.number))
            XCTAssertThrowsError(try value.provide(self.number, value: 1))
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        try await runtime.start([PluginSelection("empty")])
        try await runtime.stop()
        XCTAssertThrowsError(try context?.scope.onDispose {})
    }

    func testDeclaredServiceMustActuallyBeRegistered() async throws {
        let plugin = PluginRegistration(
            descriptor: PluginDescriptor(id: "empty", provides: [number.reference])
        ) { _, _ in }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        do {
            try await runtime.start([PluginSelection("empty")])
            XCTFail("An incomplete factory became ready")
        } catch {
            let failure = try XCTUnwrap(error as? PluginActivationFailure)
            XCTAssertEqual(failure.pluginID, "empty")
            XCTAssertEqual(failure.cause as? PluginRuntimeError, .missingRegistration(plugin: "empty", service: "number"))
        }
    }

    func testOldContextCannotReachANewerGeneration() async throws {
        var contexts: [PluginContext] = []
        let provider = PluginRegistration(
            descriptor: PluginDescriptor(id: "provider", provides: [number.reference])
        ) { context, _ in
            contexts.append(context)
            try context.provide(self.number, value: contexts.count)
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([provider]))
        try await runtime.start([PluginSelection("provider")])
        let firstGeneration = try XCTUnwrap(runtime.generation)
        try await runtime.stop()
        try await runtime.start([PluginSelection("provider")])
        XCTAssertNotEqual(firstGeneration, runtime.generation)
        XCTAssertFalse(contexts[0].isCurrent)
        XCTAssertTrue(contexts[1].isCurrent)
        XCTAssertThrowsError(try contexts[0].provide(number, value: 100))
        XCTAssertEqual(try runtime.service(number), 2)
        try await runtime.stop()
    }
}
