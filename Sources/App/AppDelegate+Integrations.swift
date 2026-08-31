import Combine
import Foundation
import Network

@MainActor
extension AppDelegate {
    func observeIntegrationSettings() {
        let settings = AppSettings.shared
        settings.$developerInterfaceEnabled
            .combineLatest(settings.$developerHTTPPort, settings.$developerHTTPToken)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.configureIntegrationHTTPServer()
                self?.configureIntegrationXPCServer()
            }
            .store(in: &cancellables)
    }

    func configureIntegrationHTTPServer() {
        let settings = AppSettings.shared
        guard settings.developerInterfaceEnabled else {
            stopIntegrationHTTPServer(resetService: true)
            return
        }

        let port = settings.developerHTTPPort
        let token = settings.developerHTTPToken
        if integrationHTTPServer != nil, integrationHTTPPort == port, integrationHTTPToken == token {
            return
        }

        stopIntegrationHTTPServer(resetService: true)

        var server: IntegrationHTTPServer!
        server = IntegrationHTTPServer(
            port: port,
            service: integrationService,
            coordinator: integrationSessionCoordinator,
            registry: integrationClientRegistry,
            settingsProvider: { .live },
            onFailure: { [weak self, weak server] error in
                self?.integrationHTTPServerFailed(server, error: error)
            }
        )

        do {
            try server.start()
            integrationHTTPServer = server
            integrationHTTPPort = port
            integrationHTTPToken = token
            Log.info("Integration HTTP server started on 127.0.0.1:\(port)")
        } catch {
            integrationHTTPServer = nil
            integrationHTTPPort = nil
            integrationHTTPToken = nil
            Log.error("Failed to start integration HTTP server on 127.0.0.1:\(port): \(error.localizedDescription)")
        }
    }

    func stopIntegrationHTTPServer(resetService: Bool = false) {
        guard let server = integrationHTTPServer else {
            if resetService {
                resetIntegrationService()
            }
            return
        }
        server.stop()
        integrationHTTPServer = nil
        integrationHTTPPort = nil
        integrationHTTPToken = nil
        if resetService {
            resetIntegrationService()
        }
        Log.info("Integration HTTP server stopped")
    }

    func integrationHTTPServerFailed(_ server: IntegrationHTTPServer?, error: NWError) {
        guard let server, integrationHTTPServer === server else { return }
        server.stop()
        integrationHTTPServer = nil
        integrationHTTPPort = nil
        integrationHTTPToken = nil
        resetIntegrationService()
        Log.error("Integration HTTP server failed: \(error.localizedDescription)")
    }

    func resetIntegrationService() {
        stopIntegrationXPCServer()
        integrationSessionCoordinator?.releaseActiveSessionForShutdown()
        integrationService = OpenTypeService(registry: integrationClientRegistry)
        integrationSessionCoordinator = makeIntegrationSessionCoordinator(service: integrationService)
        configureIntegrationXPCServer()
    }

    func configureIntegrationXPCServer() {
        guard AppSettings.shared.developerInterfaceEnabled else {
            stopIntegrationXPCServer()
            return
        }
        guard integrationXPCServer == nil else { return }
        let server = IntegrationXPCServer(
            service: integrationService,
            coordinator: integrationSessionCoordinator,
            registry: integrationClientRegistry,
            settingsProvider: { .live }
        )
        server.start()
        integrationXPCServer = server
    }

    func stopIntegrationXPCServer() {
        integrationXPCServer?.stop()
        integrationXPCServer = nil
    }

    func makeIntegrationSessionCoordinator(service: OpenTypeService) -> InputSessionCoordinator {
        InputSessionCoordinator(
            service: service,
            textProcessor: textProcessor,
            isUserWorkflowBusy: { [weak self] in
                self?.appState.isBusy ?? false
            }
        )
    }
}
