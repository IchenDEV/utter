import Foundation
import UtterContracts
import UtterEvaluation
import UtterMediaContracts
import UtterRuntime

extension VoiceEvaluationCase {
    @MainActor
    func request(model: URL, modelID: String, maxTokens: Int, runtime: PluginRuntime, transcript: String? = nil) throws -> ProcessingRequest {
        let inputLanguage: InputLanguage
        switch language {
        case "zh", "zh-Hans", "zh-Hant": inputLanguage = .chinese
        case "en": inputLanguage = .english
        case "ja": inputLanguage = .japanese
        case "ko": inputLanguage = .korean
        case "yue": inputLanguage = .cantonese
        default: inputLanguage = .auto
        }
        var options = TextProcessingOptions(settings: SettingsValues(), inputLanguage: inputLanguage)
        options.languageStyle = LanguageStyle(rawValue: style ?? "casual")!
        options.customStylePrompt = custom_style_prompt ?? ""
        options.llmModel = modelID
        options.textProviderID = "evaluation.text"
        options.useRemoteLLM = false
        options.localLLMBackend = .mlx
        options.fallbackToMLXOnEspressoFailure = false
        let factReservation = options.fidelityPolicy == .boundedCustomTransformation ? min(768, maxTokens / 2) : 0
        options.generationTokenLimit = max(1, maxTokens - factReservation)
        options.modelLocations = .frozen(bundle: nil, directory: model)
        options.modelVersions = FrozenGenerationVersions(bundle: nil, directory: model)
        let processingMode: TextProcessingMode
        switch mode ?? "formatting" {
        case "direct": processingMode = .direct
        case "command": processingMode = .command
        case "translation":
            guard let target = target_language.flatMap(TranslationLanguage.init(rawValue:)) else {
                throw VoiceEvaluationError.invalidCase(id)
            }
            processingMode = .translation(target)
        default: processingMode = .formatting
        }
        let lexiconID: IndustryLexiconID
        if let lexicon {
            guard let selected = IndustryLexiconID(rawValue: lexicon) else { throw VoiceEvaluationError.invalidCase(id) }
            lexiconID = selected
        } else { lexiconID = SettingsValues().industryLexicon }
        let dictionary = PersonalDictionarySnapshot(entries: [], editRules: [],
            industryLexicon: try runtime.service(DataServices.lexicons).snapshot(for: lexiconID))
        return ProcessingRequest(mode: processingMode, text: transcript ?? text, options: options, dictionary: dictionary,
            screenContext: screen_context ?? "", collectsDiagnostics: true)
    }

    var recipeID: String {
        switch mode ?? "formatting" {
        case "direct": return "mode.direct"
        case "command": return "mode.command"
        case "translation": return "mode.translation"
        default: return "mode.formatting"
        }
    }
}
