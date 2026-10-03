import XCTest
@testable import UtterRuntime

@MainActor
final class PluginReadinessTests: XCTestCase {
    func testIngressIsPreparedAfterEveryFactoryAndBecomesReadyTogether() async throws {
        var trace: [String] = []
        var contexts: [PluginContext] = []
        let plugins = ["first", "second"].map { id in
            PluginRegistration(descriptor: PluginDescriptor(id: id)) { context, _ in
                contexts.append(context)
                trace.append("activate-\(id)")
                try context.scope.onReady {
                    XCTAssertEqual(contexts.count, 2)
                    XCTAssertTrue(contexts.allSatisfy { !$0.isReady })
                    trace.append("prepare-\(id)")
                }
            }
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        XCTAssertEqual(trace, ["activate-first", "activate-second", "prepare-first", "prepare-second"])
        XCTAssertTrue(contexts.allSatisfy(\.isReady))
        try await runtime.stop()
        XCTAssertTrue(contexts.allSatisfy { !$0.isReady })
        XCTAssertThrowsError(try contexts[0].scope.onReady {})
    }

    func testFactoryFailureNeverPreparesIngress() async throws {
        enum Failure: Error { case injected }
        var prepared = false
        let first = PluginRegistration(descriptor: PluginDescriptor(id: "first")) { context, _ in
            try context.scope.onReady { prepared = true }
        }
        let second = PluginRegistration(descriptor: PluginDescriptor(id: "second")) { _, _ in
            throw Failure.injected
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([first, second]))
        do {
            try await runtime.start([PluginSelection("first"), PluginSelection("second")])
            XCTFail("Failed graph became ready")
        } catch {}
        XCTAssertFalse(prepared)
        XCTAssertEqual(runtime.state, .failed)
    }

    func testReadinessFailureRevokesPreparedIngressBeforeDisposal() async throws {
        enum Failure: Error { case injected }
        var trace: [String] = []
        let first = PluginRegistration(descriptor: PluginDescriptor(id: "first")) { context, _ in
            try context.scope.onReady { trace.append("prepare") }
            try context.scope.onRevoke { trace.append("revoke") }
            try context.scope.onDispose { trace.append("dispose-first") }
        }
        let second = PluginRegistration(descriptor: PluginDescriptor(id: "second")) { context, _ in
            try context.scope.onReady { throw Failure.injected }
            try context.scope.onDispose { trace.append("dispose-second") }
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([first, second]))
        do {
            try await runtime.start([PluginSelection("first"), PluginSelection("second")])
            XCTFail("Readiness failure was ignored")
        } catch {
            XCTAssertEqual((error as? PluginActivationFailure)?.pluginID, "second")
        }
        XCTAssertEqual(trace, ["prepare", "revoke", "dispose-second", "dispose-first"])
        XCTAssertEqual(runtime.state, .failed)
    }
}
