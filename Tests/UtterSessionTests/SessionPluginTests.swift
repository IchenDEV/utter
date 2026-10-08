import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterRuntime
@testable import UtterSession

final class SessionPluginTests: XCTestCase {
    @MainActor
    func testAPIUsesScopedCredentialsAndRejectsTheRetiredGraph() async throws {
        let name = "SessionPlugin-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "developerInterfaceEnabled")
        let registrations = [DataPlugins.settings(defaults: defaults), DataPlugins.credentials(),
                             DataPlugins.notifications(), DataPlugins.integrationClients(defaults: defaults), SessionPlugins.api()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(registrations))
        try await runtime.start(registrations.map { PluginSelection($0.descriptor.id) })
        let credentials = try runtime.service(DataServices.credentials)
        credentials.update { $0.developerHTTPToken = "original" }
        let clients = try runtime.service(IntegrationServices.clients)
        let client = IntegrationClient.localHTTP(tokenID: "original")
        clients.approve(client)
        let api = try runtime.service(SessionServices.api)
        let session = try await api.createSession(InputSessionRequest(), clientID: client.id)
        credentials.update { $0.developerHTTPToken = "rotated" }
        XCTAssertThrowsError(try api.session(session.id, clientID: client.id))
        try await runtime.stop()
        do {
            _ = try await api.createSession(InputSessionRequest(), clientID: client.id)
            XCTFail("A retired API accepted a request")
        } catch { XCTAssertEqual(error as? IntegrationError, .developerInterfaceDisabled) }
    }
}
