import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension ModelPlugins {
    package static func speechProviders() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "models.speech-providers", provides: [SpeechServices.providers.reference])) { context, _ in
            let registry = ProviderRegistry<SpeechProviderRequest, any SpeechEngine>()
            try context.scope.onDispose { registry.close() }
            try context.provide(SpeechServices.providers, value: registry)
        }
    }
}
