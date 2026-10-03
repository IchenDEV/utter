import UtterContracts
import UtterRuntime

@MainActor
package enum ModelPlugins {
    package static func resourceAccess() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "models.resource-access", provides: [ModelServices.resourceAccess.reference])) { context, _ in
            let gate = LocalModelAccessGate()
            try context.scope.onDispose { await gate.close() }
            try context.provide(ModelServices.resourceAccess, value: gate)
        }
    }
}
