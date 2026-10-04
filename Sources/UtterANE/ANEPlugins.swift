import UtterContracts
import UtterRuntime

@MainActor
package enum ANEPlugins {
    package static func text() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "generation.ane",
            requires: [GenerationServices.providers.required, ModelServices.resourceAccess.required, ModelServices.files.required, IntegrationServices.diagnostics.required],
            provides: [GenerationServices.ane.reference]
        )) { context, _ in
            let registry = try context.require(GenerationServices.providers)
            let service = ANEGenerationService(
                files: try context.require(ModelServices.files), access: try context.require(ModelServices.resourceAccess),
                log: Log(service: try context.require(IntegrationServices.diagnostics))
            )
            try context.scope.onDispose { await service.close() }
            let descriptor = ProviderDescriptor(id: "generation.ane", legacyIDs: [LocalLLMBackend.espresso.rawValue], displayName: "ANE-LM", modelLocation: .bundle)
            try registry.register(ProviderDefinition(descriptor: descriptor, reset: { await service.unload() }) { _ in service }, scope: context.scope)
            try context.provide(GenerationServices.ane, value: descriptor)
        }
    }
}
