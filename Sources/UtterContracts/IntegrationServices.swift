import Foundation
import UtterRuntime

package protocol IntegrationClientStore: AnyObject {
    func observeAuthorization(_ callback: @escaping () -> Void) -> UUID
    func removeAuthorizationObserver(_ id: UUID)
    func approvedClients() -> [IntegrationClient]
    func client(id: String) -> IntegrationClient?
    func approve(_ client: IntegrationClient)
    func revoke(clientID: String)
    func markUsed(clientID: String, at date: Date)
    func isAuthorized(clientID: String, capability: IntegrationClient.Capability) -> Bool
}

package protocol DiagnosticsService: Sendable {
    func info(_ message: String)
    func sensitive(_ message: String)
    func error(_ message: String)
}

package struct IntegrationServiceSettings {
    package var developerInterfaceEnabled: Bool
    package var httpToken: String

    package init(developerInterfaceEnabled: Bool, httpToken: String) {
        self.developerInterfaceEnabled = developerInterfaceEnabled
        self.httpToken = httpToken
    }
}

package enum IntegrationServices {
    package static let clients = ServiceKey<any IntegrationClientStore>("data.integration-clients")
    package static let diagnostics = ServiceKey<any DiagnosticsService>("data.diagnostics")
}
