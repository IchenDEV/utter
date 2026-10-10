import UtterContracts
import UtterRuntime

@MainActor
package enum IngressPlugins {
    package static func hotkeySessions() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "ingress.hotkey-sessions", requires: [
            MacServices.hotkeys.required, SessionServices.execution.required, DataServices.settings.required,
            IntegrationServices.diagnostics.required
        ])) { context, _ in
            let binding = HotkeySessionBinding(hotkeys: try context.require(MacServices.hotkeys),
                execution: try context.require(SessionServices.execution), settings: try context.require(DataServices.settings),
                diagnostics: try context.require(IntegrationServices.diagnostics))
            try context.scope.onReady { binding.start() }
            try context.scope.onRevoke { binding.revoke() }
            try context.scope.onDispose { await binding.close() }
        }
    }
}
