import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension IngressPlugins {
    package static func remoteSessions() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "ingress.remote-sessions", requires: [
            RemoteMicServices.control.required, DataServices.settings.required,
            SessionServices.execution.required, IntegrationServices.diagnostics.required
        ])) { context, _ in
            let binding = RemoteSessionBinding(remote: try context.require(RemoteMicServices.control),
                settings: try context.require(DataServices.settings), execution: try context.require(SessionServices.execution),
                diagnostics: try context.require(IntegrationServices.diagnostics))
            try context.scope.onReady { binding.start() }
            try context.scope.onRevoke { binding.revoke() }
            try context.scope.onDispose { await binding.close() }
        }
    }

    package static func http() -> PluginRegistration { transport(id: "ingress.http", kind: .http) }
    package static func xpc() -> PluginRegistration { transport(id: "ingress.xpc", kind: .xpc) }

    private static func transport(id: String, kind: TransportController.Kind) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: id, requires: [
            SessionServices.api.required, IntegrationServices.clients.required,
            DataServices.settings.required, DataServices.credentials.required,
            IntegrationServices.diagnostics.required
        ])) { context, _ in
            let controller = TransportController(kind: kind, api: try context.require(SessionServices.api),
                clients: try context.require(IntegrationServices.clients), settings: try context.require(DataServices.settings),
                credentials: try context.require(DataServices.credentials), diagnostics: try context.require(IntegrationServices.diagnostics),
                isReady: { context.isReady })
            try context.scope.onReady { controller.start() }
            try context.scope.onRevoke { controller.revoke() }
            try context.scope.onDispose { await controller.close() }
        }
    }
}
