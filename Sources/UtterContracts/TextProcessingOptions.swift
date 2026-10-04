import Foundation

package struct GenerationOptions {
    package let maxTokens: Int
    package let temperature: Double
    package init(maxTokens: Int, temperature: Double) { self.maxTokens = maxTokens; self.temperature = temperature }
}

package struct TextProcessingOptions {
    package enum FidelityPolicy {
        case faithfulCorrection
        case boundedCustomTransformation
    }

    package var modelLocations = FrozenGenerationLocations.unresolved
    package var modelVersions: FrozenGenerationVersions?
    package var inputLanguage: InputLanguage
    package var languageStyle: LanguageStyle
    package var customStylePrompt: String
    package var llmModel: String
    package var textProviderID: String?
    package var fallbackProviderID = "generation.mlx"
    package var imageProviderID = "generation.mlx-image"
    package var useRemoteLLM: Bool
    package var localLLMBackend: LocalLLMBackend
    package var espressoModelPath: String
    package var fallbackToMLXOnEspressoFailure: Bool
    package var remoteBaseURL: String
    package var remoteAPIKey: String
    package var remoteModel: String
    package var remoteProvider: RemoteProvider
    package var screenContextMode: ScreenContextMode
    package var useCustomSystemPrompt: Bool
    package var customSystemPrompt: String

    package var fidelityPolicy: FidelityPolicy {
        let hasCustomSystemPrompt = useCustomSystemPrompt
            && !customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasCustomSystemPrompt
            ? .boundedCustomTransformation
            : .faithfulCorrection
    }

    package init(settings: SettingsValues, inputLanguage: InputLanguage? = nil) {
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
