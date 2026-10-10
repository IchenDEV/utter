import XCTest
import UtterBuiltins
import UtterRuntime

@MainActor
final class BuiltinRegistrationPolicyTests: XCTestCase {
    func testReplacementKeepsOneProviderAndItsScopedLifetime() async throws {
        let value = ServiceKey<String>("fixture.value")
        var originalStarted = false
        var disposed = false
        let original = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.provider", provides: [value.reference])) { context, _ in
            originalStarted = true
            try context.provide(value, value: "original")
        }
        let replacement = PluginRegistration(descriptor: original.descriptor) { context, _ in
            try context.provide(value, value: "replacement")
            try context.scope.onDispose { disposed = true }
        }
        let registrations = try BuiltinRegistrationPolicy.replacing([original], with: [replacement])
        let runtime = PluginRuntime(catalog: try PluginCatalog(registrations))
        try await runtime.start([PluginSelection("fixture.provider")])
        XCTAssertEqual(try runtime.service(value), "replacement")
        XCTAssertFalse(originalStarted)
        try await runtime.stop()
        XCTAssertTrue(disposed)
    }

    func testUnknownAndDuplicateReplacementsFailBeforeActivation() async throws {
        let original = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.provider")) { _, _ in }
        let unknown = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.unknown")) { _, _ in }
        XCTAssertThrowsError(try BuiltinRegistrationPolicy.replacing([original], with: [unknown])) {
            XCTAssertEqual($0 as? PluginRuntimeError, .unknownPlugin("fixture.unknown"))
        }
        XCTAssertThrowsError(try BuiltinRegistrationPolicy.replacing([original], with: [original, original])) {
            XCTAssertEqual($0 as? PluginRuntimeError, .duplicatePlugin("fixture.provider"))
        }
    }
}
