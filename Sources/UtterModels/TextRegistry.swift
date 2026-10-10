import UtterContracts
import UtterRuntime

@MainActor
extension ModelPlugins {
    package static func textProviders() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "models.text-providers", provides: [GenerationServices.providers.reference])) { context, _ in
            let registry = ProviderRegistry<GenerationPurpose, any TextGenerationService>()
            try context.scope.onRevoke { registry.close() }
            try context.provide(GenerationServices.providers, value: registry)
        }
    }
}
