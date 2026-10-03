import XCTest
import UtterContracts
import UtterRuntime
@testable import UtterModels

@MainActor
final class ProviderRegistryTests: XCTestCase {
    func testMetadataRegistrationDoesNotConstructAProviderAndLegacyIDResolvesTheSameFactory() async throws {
        let key = ServiceKey<any ProviderCatalog<String, String>>("test.providers")
        var created = 0
        let registry = ProviderRegistry<String, String>()
        let host = PluginRegistration(descriptor: PluginDescriptor(id: "host", provides: [key.reference])) { context, _ in
            try context.scope.onDispose { registry.close() }
            try context.provide(key, value: registry)
        }
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "engine", requires: [key.required])) { context, _ in
            let service = try context.require(key)
            try service.register(ProviderDefinition(descriptor: ProviderDescriptor(id: "speech.replaceable", legacyIDs: ["legacy"], displayName: "Synthetic")) { request in
                created += 1
                return request.uppercased()
            }, scope: context.scope)
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([host, plugin]))
        try await runtime.start([PluginSelection("engine"), PluginSelection("host")])
        let service = try runtime.service(key)
        XCTAssertEqual(created, 0)
        XCTAssertEqual(service.descriptors.map(\.id), ["speech.replaceable"])
        let first = try await service.create(id: "legacy", request: "first")
        XCTAssertEqual(first, "FIRST")
        XCTAssertEqual(created, 1)
        try await runtime.stop()
        XCTAssertTrue(service.descriptors.isEmpty)
        do { _ = try await service.create(id: "legacy", request: "late"); XCTFail("Disposed registry constructed a provider") }
        catch ProviderCatalogError.closed {}
    }

    func testOverlappingLegacyAliasesFailActivationAndUnwindRegistration() async throws {
        let registry = ProviderRegistry<String, String>()
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "providers")) { context, _ in
            try registry.register(ProviderDefinition(descriptor: ProviderDescriptor(id: "one", legacyIDs: ["old"], displayName: "One")) { $0 }, scope: context.scope)
            try registry.register(ProviderDefinition(descriptor: ProviderDescriptor(id: "two", legacyIDs: ["old"], displayName: "Two")) { $0 }, scope: context.scope)
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        do { try await runtime.start([PluginSelection("providers")]); XCTFail("Expected alias conflict") }
        catch let failure as PluginActivationFailure {
            XCTAssertEqual(failure.cause as? ProviderCatalogError, .duplicateIdentifier("old"))
            XCTAssertTrue(failure.cleanupFailures.isEmpty)
        }
        XCTAssertTrue(registry.descriptors.isEmpty)
        try await runtime.stop()
    }
}
