import UtterPresentationContracts
import UtterContracts
import AppKit
import Foundation

@MainActor
final class IntegrationXPCServer: NSObject, NSXPCListenerDelegate {
    private var closed = false
    private var retired: [IntegrationXPCConnectionHandler] = []
    private let log: Log
    private let service: any InputSessionService
    private let registry: any IntegrationClientStore
    private let settingsProvider: @MainActor () -> IntegrationServiceSettings
    private var listener: NSXPCListener?
    private var handlers: [ObjectIdentifier: IntegrationXPCConnectionHandler] = [:]

    init(
        service: any InputSessionService,
        diagnostics: any DiagnosticsService,
        registry: any IntegrationClientStore,
        settingsProvider: @escaping @MainActor () -> IntegrationServiceSettings
    ) {
        log = Log(service: diagnostics)
        self.service = service
        self.registry = registry
        self.settingsProvider = settingsProvider
    }

    func start() {
        guard !closed, listener == nil else { return }
        let listener = NSXPCListener(machServiceName: IntegrationXPCConstants.machServiceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        log.info("Integration XPC server started: \(IntegrationXPCConstants.machServiceName)")
    }

    func stop() {
        guard !closed else { return }
        closed = true
        listener?.invalidate()
        listener = nil
        for handler in handlers.values {
            handler.invalidate()
            retired.append(handler)
        }
        handlers.removeAll()
        log.info("Integration XPC server stopped")
    }

    func close() async {
        stop()
        for handler in retired { await handler.close() }
        retired.removeAll()
    }

    nonisolated func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                accept(connection)
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                accept(connection)
            }
        }
    }

    private func accept(_ connection: NSXPCConnection) -> Bool {
        guard !closed, settingsProvider().developerInterfaceEnabled else {
            return false
        }
        guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier) else {
            return false
        }

        let client = IntegrationClient.appIdentity(for: app, transport: .xpc)
        guard registry.isAuthorized(clientID: client.id, capability: .record) else {
            log.info("[IntegrationXPC] rejected unregistered client: \(client.displayName)")
            return false
        }

        let handler = IntegrationXPCConnectionHandler(
            clientID: client.id,
            service: service,
            log: log
        )
        let id = ObjectIdentifier(connection)
        handlers[id] = handler

        connection.exportedInterface = NSXPCInterface(with: OpenTypeXPCProtocol.self)
        connection.exportedObject = handler
        connection.invalidationHandler = { [weak self, weak handler] in
            Task { @MainActor in
                self?.retire(id)
            }
        }
        connection.interruptionHandler = { [weak self, weak handler] in
            Task { @MainActor in
                self?.retire(id)
            }
        }
        connection.resume()
        registry.markUsed(clientID: client.id, at: Date())
        return true
    }

    private func retire(_ id: ObjectIdentifier) {
        guard let handler = handlers.removeValue(forKey: id) else { return }
        handler.invalidate()
        retired.append(handler)
    }
}
