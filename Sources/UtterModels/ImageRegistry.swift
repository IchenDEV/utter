import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension ModelPlugins {
    package static func imageProviders() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "models.image-providers", provides: [ImageGenerationServices.providers.reference])) { context, _ in
            let registry = ProviderRegistry<GenerationPurpose, any ImageGenerationService>()
            try context.scope.onDispose { registry.close() }
            try context.provide(ImageGenerationServices.providers, value: registry)
        }
    }
}
