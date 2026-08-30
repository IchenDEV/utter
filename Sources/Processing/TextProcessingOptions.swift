import Foundation

struct GenerationOptions {
    let maxTokens: Int
    let temperature: Double
}

struct TextProcessingOptions {
    enum FidelityPolicy {
        case faithfulCorrection
        case boundedCustomTransformation
    }

    var inputLanguage: InputLanguage
    var languageStyle: LanguageStyle
    var customStylePrompt: String
    var llmModel: String
    var useRemoteLLM: Bool
    var localLLMBackend: LocalLLMBackend
    var espressoModelPath: String
    var fallbackToMLXOnEspressoFailure: Bool
    var remoteBaseURL: String
    var remoteAPIKey: String
    var remoteModel: String
    var remoteProvider: RemoteProvider
    var screenContextMode: ScreenContextMode
    var useCustomSystemPrompt: Bool
    var customSystemPrompt: String

    var fidelityPolicy: FidelityPolicy {
        let hasCustomSystemPrompt = useCustomSystemPrompt
            && !customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasCustomSystemPrompt
            ? .boundedCustomTransformation
            : .faithfulCorrection
    }

    init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
        self.inputLanguage = inputLanguage ?? settings.inputLanguage
        self.languageStyle = settings.languageStyle
        self.customStylePrompt = settings.customStylePrompt
        self.llmModel = settings.llmModel
        self.useRemoteLLM = settings.useRemoteLLM
        self.localLLMBackend = settings.localLLMBackend
        self.espressoModelPath = settings.espressoModelPath
        self.fallbackToMLXOnEspressoFailure = settings.fallbackToMLXOnEspressoFailure
        self.remoteBaseURL = settings.remoteBaseURL
        self.remoteAPIKey = settings.remoteAPIKey
        self.remoteModel = settings.remoteModel
        self.remoteProvider = settings.remoteProvider
        self.screenContextMode = settings.screenContextMode
        self.useCustomSystemPrompt = settings.useCustomSystemPrompt
        self.customSystemPrompt = settings.customSystemPrompt
    }
}
