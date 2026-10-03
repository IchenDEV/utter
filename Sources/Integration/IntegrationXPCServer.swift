import UtterContracts
import AppKit
import Foundation

@MainActor
final class IntegrationXPCServer: NSObject, NSXPCListenerDelegate {
    private let service: OpenTypeService
    private let coordinator: InputSessionCoordinator
    private let registry: IntegrationClientRegistry
    private let settingsProvider: @MainActor () -> IntegrationServiceSettings
    private var listener: NSXPCListener?
    private var handlers: [ObjectIdentifier: IntegrationXPCConnectionHandler] = [:]

    init(
        service: OpenTypeService,
        coordinator: InputSessionCoordinator,
        registry: IntegrationClientRegistry,
        settingsProvider: @escaping @MainActor () -> IntegrationServiceSettings = { .live }
    ) {
        self.service = service
        self.coordinator = coordinator
        self.registry = registry
        self.settingsProvider = settingsProvider
    }

    func start() {
        guard listener == nil else { return }
        let listener = NSXPCListener(machServiceName: IntegrationXPCConstants.machServiceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        Log.info("Integration XPC server started: \(IntegrationXPCConstants.machServiceName)")
    }

    func stop() {
        listener?.invalidate()
        listener = nil
        for handler in handlers.values {
            handler.invalidate()
        }
        handlers.removeAll()
        Log.info("Integration XPC server stopped")
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
        guard settingsProvider().developerInterfaceEnabled else {
            return false
        }
        guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier) else {
            return false
        }

        let client = IntegrationClient.appIdentity(for: app, transport: .xpc)
        guard registry.isAuthorized(clientID: client.id, capability: .record) else {
            Log.info("[IntegrationXPC] rejected unregistered client: \(client.displayName)")
            return false
        }

        let handler = IntegrationXPCConnectionHandler(
            clientID: client.id,
            service: service,
            coordinator: coordinator
        )
        let id = ObjectIdentifier(connection)
        handlers[id] = handler

        connection.exportedInterface = NSXPCInterface(with: OpenTypeXPCProtocol.self)
        connection.exportedObject = handler
        connection.invalidationHandler = { [weak self, weak handler] in
            Task { @MainActor in
                handler?.invalidate()
                self?.handlers[id] = nil
            }
        }
        connection.interruptionHandler = { [weak self, weak handler] in
            Task { @MainActor in
                handler?.invalidate()
                self?.handlers[id] = nil
            }
        }
        connection.resume()
        registry.markUsed(clientID: client.id)
        return true
    }
}
