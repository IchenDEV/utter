import UtterContracts
import UtterMediaContracts

@MainActor
struct VoiceWorkflowDependencies {
    let settings: any SettingsService
    let credentials: any CredentialsService
    let configuration: (any ConfigurationService)?
    let dictionary: any DictionaryService
    let lexicons: any LexiconService
    let clients: any IntegrationClientStore
    let files: any ModelFilesService
    let access: any ModelResourceAccess
    let speech: any ProviderCatalog<SpeechProviderRequest, any SpeechEngine>
    let generation: any ProviderCatalog<GenerationPurpose, any TextGenerationService>
    let recipes: any ProviderCatalog<Void, any ModeRecipeService>
    let capture: any CaptureService
    let audioFiles: any AudioFileService
    let evidence: any SpeechEvidenceService
    let output: any OutputService
    let targets: any TargetCaptureService
    let memory: (any MemoryService)?
    let screen: (any ScreenCaptureService)?
    let sounds: (any SoundService)?
    let correction: (any CorrectionControlService)?
    let log: any DiagnosticsService
}
