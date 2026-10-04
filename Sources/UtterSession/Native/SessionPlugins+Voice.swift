import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension SessionPlugins {
    package static func voiceWorkflows() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "session.voice-workflows",
            requires: [DataServices.settings.required, DataServices.credentials.required, DataServices.configuration.optional,
                       DataServices.dictionary.required, DataServices.lexicons.required, IntegrationServices.clients.required,
                       ModelServices.files.required, ModelServices.resourceAccess.required,
                       SpeechServices.providers.required, GenerationServices.providers.required, ModeServices.recipes.required,
                       AudioServices.capture.required, AudioServices.files.required, AudioServices.evidence.required,
                       MacServices.output.required, MacServices.target.required, IntegrationServices.diagnostics.required,
                       DataServices.memory.optional, MacServices.screen.optional, MacServices.sounds.optional, MacServices.correction.optional],
            provides: [SessionServices.workflows.reference]
        )) { context, _ in
            let dependencies = VoiceWorkflowDependencies(
                settings: try context.require(DataServices.settings), credentials: try context.require(DataServices.credentials),
                configuration: try context.optional(DataServices.configuration), dictionary: try context.require(DataServices.dictionary),
                lexicons: try context.require(DataServices.lexicons), clients: try context.require(IntegrationServices.clients),
                files: try context.require(ModelServices.files), access: try context.require(ModelServices.resourceAccess),
                speech: try context.require(SpeechServices.providers), generation: try context.require(GenerationServices.providers),
                recipes: try context.require(ModeServices.recipes), capture: try context.require(AudioServices.capture),
                audioFiles: try context.require(AudioServices.files), evidence: try context.require(AudioServices.evidence),
                output: try context.require(MacServices.output), targets: try context.require(MacServices.target),
                memory: try context.optional(DataServices.memory), screen: try context.optional(MacServices.screen),
                sounds: try context.optional(MacServices.sounds), correction: try context.optional(MacServices.correction),
                log: try context.require(IntegrationServices.diagnostics)
            )
            let factory = VoiceWorkflowFactory(dependencies: dependencies, isReady: { context.isReady })
            try context.provide(SessionServices.workflows, value: factory)
        }
    }
}
