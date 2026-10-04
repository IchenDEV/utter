import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
package enum MLXPlugins {
    package static func text() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "generation.mlx",
            requires: [GenerationServices.providers.required, ModelServices.resourceAccess.required, ModelServices.files.required, IntegrationServices.diagnostics.required, ModelServices.artifacts.optional],
            provides: [GenerationServices.mlx.reference]
        )) { context, _ in
            try context.optional(ModelServices.artifacts)?.register(MLXModelArtifacts.text, scope: context.scope)
            let registry = try context.require(GenerationServices.providers)
            let files = try context.require(ModelServices.files)
            let access = try context.require(ModelServices.resourceAccess)
            let log = Log(service: try context.require(IntegrationServices.diagnostics))
            let inference = MLXGenerationService(files: files, access: access, log: log)
            let benchmark = MLXGenerationService(files: files, access: access, log: log)
            try context.scope.onDispose {
                await inference.close()
                await benchmark.close()
            }
            let descriptor = ProviderDescriptor(id: "generation.mlx", legacyIDs: [LocalLLMBackend.mlx.rawValue], displayName: "MLX", artifacts: MLXModelArtifacts.text)
            try registry.register(ProviderDefinition(descriptor: descriptor) { purpose in
                purpose == .benchmark ? benchmark : inference
            }, scope: context.scope)
            try context.provide(GenerationServices.mlx, value: descriptor)
        }
    }

    package static func image() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "generation.mlx-image",
            requires: [ImageGenerationServices.providers.required, ModelServices.resourceAccess.required, ModelServices.files.required, IntegrationServices.diagnostics.required],
            provides: [ImageGenerationServices.mlx.reference]
        )) { context, _ in
            let registry = try context.require(ImageGenerationServices.providers)
            let service = MLXImageGenerationService(
                files: try context.require(ModelServices.files), access: try context.require(ModelServices.resourceAccess),
                log: Log(service: try context.require(IntegrationServices.diagnostics))
            )
            try context.scope.onDispose { await service.close() }
            let descriptor = ProviderDescriptor(id: "generation.mlx-image", displayName: "MLX VLM")
            try registry.register(ProviderDefinition(descriptor: descriptor) { _ in service }, scope: context.scope)
            try context.provide(ImageGenerationServices.mlx, value: descriptor)
        }
    }
}
