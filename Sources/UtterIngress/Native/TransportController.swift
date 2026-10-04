import Foundation
import UtterContracts

@MainActor
final class TransportController {
    enum Kind { case http, xpc }
    private let kind: Kind
    private let api: any InputSessionService
    private let clients: any IntegrationClientStore
    private let settings: any SettingsService
    private let credentials: any CredentialsService
    private let diagnostics: any DiagnosticsService
    private let isReady: () -> Bool
    private var http: IntegrationHTTPServer?
    private var xpc: IntegrationXPCServer?
    private var settingsObservation: UUID?
    private var credentialObservation: UUID?
    private var configuration: Configuration?
    private var closed = false
    private var shutdowns: [UUID: Task<Void, Never>] = [:]
    private struct Configuration: Equatable {
        let enabled: Bool
        let port: Int
        let token: String
    }

    init(kind: Kind, api: any InputSessionService, clients: any IntegrationClientStore,
         settings: any SettingsService, credentials: any CredentialsService,
         diagnostics: any DiagnosticsService, isReady: @escaping () -> Bool) {
        self.kind = kind; self.api = api; self.clients = clients; self.settings = settings
        self.credentials = credentials; self.diagnostics = diagnostics; self.isReady = isReady
    }

    func start() {
        guard !closed else { return }
        settingsObservation = settings.observe { [weak self] _ in self?.configure() }
        credentialObservation = credentials.observe { [weak self] _ in self?.configure() }
        configure()
    }

    private func configure() {
        guard !closed, isReady() else { return }
        let next = Configuration(enabled: settings.values.developerInterfaceEnabled,
            port: settings.values.developerHTTPPort, token: credentials.snapshot.developerHTTPToken)
        guard configuration != next else { return }
        stopTransport()
        configuration = next
        guard next.enabled else { return }
        let currentSettings: @MainActor () -> IntegrationServiceSettings = { [settings, credentials] in
            IntegrationServiceSettings(developerInterfaceEnabled: settings.values.developerInterfaceEnabled,
                                       httpToken: credentials.snapshot.developerHTTPToken)
        }
        switch kind {
        case .http:
            let server = IntegrationHTTPServer(port: next.port, service: api, registry: clients,
                settingsProvider: currentSettings, onFailure: { [weak self] error in
                    self?.diagnostics.error("Integration HTTP listener failed: \(error.localizedDescription)")
                    self?.stopTransport()
                })
            do { try server.start(); http = server }
            catch { diagnostics.error("Integration HTTP listener could not start: \(error.localizedDescription)") }
        case .xpc:
            let server = IntegrationXPCServer(service: api, diagnostics: diagnostics, registry: clients,
                settingsProvider: currentSettings)
            server.start()
            xpc = server
        }
    }

    private func stopTransport() {
        if let http {
            http.stop()
            drain { await http.close() }
        }
        if let xpc {
            xpc.stop()
            drain { await xpc.close() }
        }
        http = nil; xpc = nil
    }

    private func drain(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        shutdowns[id] = Task { [weak self] in
            await operation()
            self?.shutdowns[id] = nil
        }
    }

    func revoke() {
        guard !closed else { return }
        closed = true
        if let settingsObservation { settings.removeObserver(settingsObservation) }
        if let credentialObservation { credentials.removeObserver(credentialObservation) }
        settingsObservation = nil; credentialObservation = nil
        stopTransport()
    }

    func close() async {
        revoke()
        for task in Array(shutdowns.values) { await task.value }
        shutdowns.removeAll()
    }
}
