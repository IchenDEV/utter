import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension ProcessingPlugins {
    package static func text(additionalDependencies: [ServiceRequirement] = []) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "processing.text",
            requires: [
                DataServices.settings.required, DataServices.credentials.optional,
                DataServices.dictionary.required, DataServices.lexicons.required,
                GenerationServices.providers.required, ImageGenerationServices.providers.optional,
                ModelServices.resourceAccess.required, ModelServices.files.required,
                IntegrationServices.diagnostics.required,
                GenerationServices.mlx.optional, GenerationServices.ane.optional, GenerationServices.remote.optional,
                ImageGenerationServices.mlx.optional,
            ] + additionalDependencies,
            provides: [ProcessingServices.text.reference]
        )) { context, _ in
            let settings = try context.require(DataServices.settings)
            let credentials = try context.optional(DataServices.credentials)
            let dictionary = try context.require(DataServices.dictionary)
            let lexicons = try context.require(DataServices.lexicons)
            let snapshot = { credentials?.snapshot.applying(to: settings.values) ?? settings.values }
            let processor = TextProcessor(
                providers: try context.require(GenerationServices.providers),
                imageProviders: try context.optional(ImageGenerationServices.providers),
                access: try context.require(ModelServices.resourceAccess), files: try context.require(ModelServices.files),
                settings: snapshot,
                dictionary: { dictionary.snapshot(industryLexicon: lexicons.snapshot(for: snapshot().industryLexicon), bundleIdentifier: nil, languageCode: nil) },
                log: Log(service: try context.require(IntegrationServices.diagnostics))
            )
            let service = ScopedProcessingService(processor: processor, isCurrent: { context.isCurrent })
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onDispose { await service.close() }
            try context.provide(ProcessingServices.text, value: service)
        }
    }
}
