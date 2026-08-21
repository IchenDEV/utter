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
        let profile = ProductEdition.current
        self.inputLanguage = inputLanguage ?? settings.inputLanguage
        self.languageStyle = profile.capabilities.customPrompts ? settings.languageStyle : .professional
        self.customStylePrompt = profile.capabilities.customPrompts ? settings.customStylePrompt : ""
        self.llmModel = profile.capabilities.modelManagement
            ? settings.llmModel
            : profile.formattingModel.id
        self.useRemoteLLM = profile.capabilities.remoteInference && settings.useRemoteLLM
        self.remoteBaseURL = profile.capabilities.remoteInference ? settings.remoteBaseURL : ""
        self.remoteAPIKey = profile.capabilities.remoteInference ? settings.remoteAPIKey : ""
        self.remoteModel = profile.capabilities.remoteInference ? settings.remoteModel : ""
        self.remoteProvider = settings.remoteProvider
        self.screenContextMode = settings.screenContextMode
        self.useCustomSystemPrompt = profile.capabilities.customPrompts && settings.useCustomSystemPrompt
        self.customSystemPrompt = profile.capabilities.customPrompts ? settings.customSystemPrompt : ""
    }
}
