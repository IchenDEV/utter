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

    private let integrations = "presentation.integrations"
    private let remote = "presentation.remote"
    private let configuration = "presentation.configuration"

    private func mountedTabs(mounting ids: [String]) async throws -> (tabs: [SettingsTab], runtime: PluginRuntime) {
        let fixture = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.data",
            provides: [IntegrationServices.clients.reference, DataServices.configuration.reference,
                       IntegrationServices.diagnostics.reference])) { context, _ in
            try context.provide(IntegrationServices.clients, value: Clients())
            try context.provide(DataServices.configuration, value: Configuration())
            try context.provide(IntegrationServices.diagnostics, value: TestDiagnostics.service)
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([fixture, PresentationPlugins.catalog(),
            PresentationPlugins.integrations(), PresentationPlugins.remote(), PresentationPlugins.configuration()]))
        try await runtime.start((["fixture.data", "presentation.catalog"] + ids).map { PluginSelection($0) })
        let catalog = try runtime.service(PresentationServices.catalog)
        return (SettingsTabLayout.tabs(from: catalog.contributions(for: .settings)), runtime)
    }

    private func assertTab(mounting ids: [String], members expected: [String], file: StaticString = #filePath,
                           line: UInt = #line) async throws {
        let (tabs, runtime) = try await mountedTabs(mounting: ids)
        XCTAssertEqual(tabs.map(\.id), [SettingsGroup.integrations.id], file: file, line: line)
        XCTAssertEqual(tabs.first?.members.map(\.id), expected, file: file, line: line)
        try await runtime.stop()
    }

    func testIntegrationsRemoteAndPluginsRegisterIntoOneTabInOrder() async throws {
        try await assertTab(mounting: [configuration, remote, integrations], members: [integrations, remote, configuration])
    }

    func testDisablingAnyOneRealPluginLeavesTheOtherTwoInTheTab() async throws {
        try await assertTab(mounting: [configuration, remote], members: [remote, configuration])
        try await assertTab(mounting: [configuration, integrations], members: [integrations, configuration])
        try await assertTab(mounting: [remote, integrations], members: [integrations, remote])
    }

    func testAnySinglePluginStillGetsTheIntegrationsTab() async throws {
        try await assertTab(mounting: [configuration], members: [configuration])
        try await assertTab(mounting: [remote], members: [remote])
        try await assertTab(mounting: [integrations], members: [integrations])
    }

    func testNoMemberMeansNoIntegrationsTab() async throws {
        let (tabs, runtime) = try await mountedTabs(mounting: [])
        XCTAssertTrue(tabs.isEmpty)
        try await runtime.stop()
    }
}
