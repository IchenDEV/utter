import XCTest
import Foundation
import UtterContracts
import UtterPresentationContracts
import UtterRuntime
@testable import UtterPresentation

@MainActor
final class SettingsGroupPluginTests: XCTestCase {
    private final class Clients: IntegrationClientStore {
        func observeAuthorization(_ callback: @escaping () -> Void) -> UUID { UUID() }
        func removeAuthorizationObserver(_ id: UUID) {}
        func approvedClients() -> [IntegrationClient] { [] }
        func client(id: String) -> IntegrationClient? { nil }
        func approve(_ client: IntegrationClient) {}
        func revoke(clientID: String) {}
        func markUsed(clientID: String, at date: Date) {}
        func isAuthorized(clientID: String, capability: IntegrationClient.Capability) -> Bool { false }
    }

    private final class Configuration: ConfigurationService {
        var document: CompositionDocument? { nil }
        var mounted: EffectiveComposition? { nil }
        var pending: EffectiveComposition? { nil }
        var restartRequired: Bool { false }
        var sessionSnapshot: EffectiveComposition { get throws { EffectiveComposition(plugins: [], bindings: [:]) } }
        func save(_ proposed: CompositionDocument) throws {}
        func resetToShipped() throws -> URL? { nil }
    }

    private func mountedTabs(mounting ids: [String]) async throws -> (tabs: [SettingsTab], runtime: PluginRuntime) {
        let fixture = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.data",
            provides: [IntegrationServices.clients.reference, DataServices.configuration.reference])) { context, _ in
            try context.provide(IntegrationServices.clients, value: Clients())
            try context.provide(DataServices.configuration, value: Configuration())
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([fixture, PresentationPlugins.catalog(),
            PresentationPlugins.integrations(), PresentationPlugins.configuration()]))
        try await runtime.start((["fixture.data", "presentation.catalog"] + ids).map { PluginSelection($0) })
        let catalog = try runtime.service(PresentationServices.catalog)
        return (SettingsTabLayout.tabs(from: catalog.contributions(for: .settings)), runtime)
    }

    func testIntegrationsAndPluginsRegisterIntoOneTabInOrder() async throws {
        let (tabs, runtime) = try await mountedTabs(mounting: ["presentation.configuration", "presentation.integrations"])
        XCTAssertEqual(tabs.map(\.id), [SettingsGroup.integrations.id])
        XCTAssertEqual(tabs.first?.members.map(\.id), ["presentation.integrations", "presentation.configuration"])
        try await runtime.stop()
    }

    func testDisablingOneRealPluginLeavesTheOtherSectionInTheTab() async throws {
        let (onlyPlugins, first) = try await mountedTabs(mounting: ["presentation.configuration"])
        XCTAssertEqual(onlyPlugins.first?.members.map(\.id), ["presentation.configuration"])
        try await first.stop()
        let (onlyIntegrations, second) = try await mountedTabs(mounting: ["presentation.integrations"])
        XCTAssertEqual(onlyIntegrations.first?.members.map(\.id), ["presentation.integrations"])
        try await second.stop()
    }
}
