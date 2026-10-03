import Foundation
import UtterContracts

extension SettingsStore {
    enum Key: String {
        case hotkeyAccessibilityPrompted
        case hotkeyType, translationHotkeyModifier, activationMode, tapInterval, speechEngine, whisperModel, llmModel
        case microphoneID, remoteMicEnabled, remoteMicGainDB, outputMode, languageStyle, customStylePrompt, playSounds
        case audioGateSensitivity, audioWeakSpeechSensitivity
        case enableStreamingRecognitionBeta
        case inputLanguage, translationTargetLanguage
        case useScreenContext, screenContextMode, enableInstantInsert, hasCompletedOnboarding, uiLanguage, historyRetention
        case enableMemory, memoryWindowMinutes, enableCorrectionLearning, industryLexicon
        case useCustomSystemPrompt, customSystemPrompt
        case useRemoteLLM, localLLMBackend, espressoModelPath, fallbackToMLXOnEspressoFailure
        case remoteProvider, remoteAPIKey, remoteBaseURL, remoteModel
        case menuBarIcon, appIconAppearance
        case volcAppKey, volcAccessKey, volcResourceId
        case qwenASRModel, qwenASRModelPath
        case preloadSpeechModelOnLaunch, preloadFormattingModelOnLaunch
        case modelStoragePath, localWhisperModelPaths, localLLMModelPaths
        case developerInterfaceEnabled, developerHTTPPort, developerHTTPToken
    }

    static func load(defaults: UserDefaults) -> SettingsValues {
        let ud = defaults
        let loadedUILanguage = UILanguage(rawValue: ud.string(forKey: Key.uiLanguage.rawValue) ?? "") ?? .chinese
        Loc.use(loadedUILanguage)
        var values = SettingsValues()
        let loadedHotkeyType = HotkeyType(rawValue: ud.string(forKey: Key.hotkeyType.rawValue) ?? "") ?? .fn
        values.hotkeyAccessibilityPrompted = ud.bool(forKey: Key.hotkeyAccessibilityPrompted.rawValue)
        values.hotkeyType = loadedHotkeyType
        let loadedTranslationModifier = HotkeyType(
            rawValue: ud.string(forKey: Key.translationHotkeyModifier.rawValue) ?? ""
        ) ?? .shift
        values.translationHotkeyModifier = loadedTranslationModifier == loadedHotkeyType
            ? SettingsValues.defaultTranslationModifier(excluding: loadedHotkeyType)
            : loadedTranslationModifier
        let savedMode = ud.string(forKey: Key.activationMode.rawValue) ?? ""
        values.activationMode = ActivationMode(rawValue: savedMode)
            ?? (savedMode.contains("长按") ? .longPress : savedMode.contains("双击") ? .doubleTap : savedMode.contains("单击") ? .toggle : nil)
            ?? .longPress
        values.tapInterval = ud.double(forKey: Key.tapInterval.rawValue).nonZero ?? 0.4
        let savedEngine = ud.string(forKey: Key.speechEngine.rawValue) ?? ""
        let loadedSpeechEngine = SpeechEngineType(rawValue: savedEngine)
            ?? (savedEngine.contains("Whisper") || savedEngine.contains("whisper") ? .whisper : nil)
            ?? .apple
        values.speechEngine = savedEngine == "mimo" ? .apple : loadedSpeechEngine
        if savedEngine == "mimo" {
            ud.set(SpeechEngineType.apple.rawValue, forKey: Key.speechEngine.rawValue)
        }
        [
            "localASRPythonPath",
            "mimoASRRepoPath",
            "mimoASRModel",
            "mimoASRModelPath",
            "mimoASRTokenizerPath",
        ].forEach(ud.removeObject(forKey:))
        values.whisperModel = ud.string(forKey: Key.whisperModel.rawValue) ?? "large-v3"
        values.llmModel = ud.string(forKey: Key.llmModel.rawValue) ?? SettingsValues.defaultLLMModelID
        values.microphoneID = ud.string(forKey: Key.microphoneID.rawValue)
        values.remoteMicEnabled = ud.bool(forKey: Key.remoteMicEnabled.rawValue)
        values.remoteMicGainDB = ud.object(forKey: Key.remoteMicGainDB.rawValue) == nil
            ? SettingsValues.defaultRemoteMicGainDB
            : min(24, max(0, ud.double(forKey: Key.remoteMicGainDB.rawValue)))
        values.audioGateSensitivity = AudioSensitivity(
            rawValue: ud.string(forKey: Key.audioGateSensitivity.rawValue) ?? ""
        ) ?? .standard
        values.audioWeakSpeechSensitivity = AudioSensitivity(
            rawValue: ud.string(forKey: Key.audioWeakSpeechSensitivity.rawValue) ?? ""
        ) ?? .standard
        let savedOutput = ud.string(forKey: Key.outputMode.rawValue) ?? ""
        values.outputMode = OutputMode(rawValue: savedOutput)
            ?? (savedOutput.contains("整理") ? .processed : nil)
            ?? .processed
        let savedStyle = ud.string(forKey: Key.languageStyle.rawValue) ?? ""
        let style = LanguageStyle.migrated(from: savedStyle)
        values.languageStyle = style
        if let savedPrompt = ud.string(forKey: Key.customStylePrompt.rawValue), !savedPrompt.isEmpty {
            values.customStylePrompt = savedPrompt
        } else {
            values.customStylePrompt = LanguageStyle.custom.defaultPrompt
        }
        values.playSounds = ud.object(forKey: Key.playSounds.rawValue) as? Bool ?? true
        values.enableStreamingRecognitionBeta = ud.object(forKey: Key.enableStreamingRecognitionBeta.rawValue) as? Bool ?? true
        values.inputLanguage = InputLanguage(rawValue: ud.string(forKey: Key.inputLanguage.rawValue) ?? "") ?? .chinese
        values.translationTargetLanguage = TranslationLanguage(
            rawValue: ud.string(forKey: Key.translationTargetLanguage.rawValue) ?? ""
        ) ?? .english
        values.useScreenContext = ud.object(forKey: Key.useScreenContext.rawValue) as? Bool ?? false
        values.screenContextMode = ScreenContextMode(rawValue: ud.string(forKey: Key.screenContextMode.rawValue) ?? "") ?? .ocr
        values.enableInstantInsert = ud.object(forKey: Key.enableInstantInsert.rawValue) as? Bool ?? false
        values.hasCompletedOnboarding = ud.bool(forKey: Key.hasCompletedOnboarding.rawValue)
        values.uiLanguage = loadedUILanguage
        values.historyRetention = HistoryRetention(rawValue: ud.string(forKey: Key.historyRetention.rawValue) ?? "") ?? .forever
        values.enableMemory = ud.object(forKey: Key.enableMemory.rawValue) as? Bool ?? true
        values.memoryWindowMinutes = (ud.integer(forKey: Key.memoryWindowMinutes.rawValue)).nonZeroInt ?? 30
        values.enableCorrectionLearning = ud.object(forKey: Key.enableCorrectionLearning.rawValue) as? Bool ?? true
        values.industryLexicon = IndustryLexiconID(
            rawValue: ud.string(forKey: Key.industryLexicon.rawValue) ?? ""
        ) ?? .general
        values.useCustomSystemPrompt = ud.bool(forKey: Key.useCustomSystemPrompt.rawValue)
        values.customSystemPrompt = ud.string(forKey: Key.customSystemPrompt.rawValue) ?? ""
        values.useRemoteLLM = ud.bool(forKey: Key.useRemoteLLM.rawValue)
        values.localLLMBackend = LocalLLMBackend(
            rawValue: ud.string(forKey: Key.localLLMBackend.rawValue) ?? ""
        ) ?? .mlx
        values.espressoModelPath = ud.string(forKey: Key.espressoModelPath.rawValue) ?? ""
        values.fallbackToMLXOnEspressoFailure = ud.object(
            forKey: Key.fallbackToMLXOnEspressoFailure.rawValue
        ) as? Bool ?? true
        values.remoteProvider = RemoteProvider(rawValue: ud.string(forKey: Key.remoteProvider.rawValue) ?? "") ?? .custom
        values.remoteAPIKey = ud.string(forKey: Key.remoteAPIKey.rawValue) ?? ""
        values.remoteBaseURL = ud.string(forKey: Key.remoteBaseURL.rawValue) ?? ""
        values.remoteModel = ud.string(forKey: Key.remoteModel.rawValue) ?? ""
        values.menuBarIcon = MenuBarIcon(rawValue: ud.string(forKey: Key.menuBarIcon.rawValue) ?? "") ?? .mic
        values.appIconAppearance = AppIconAppearance(rawValue: ud.string(forKey: Key.appIconAppearance.rawValue) ?? "") ?? .system
        values.volcAppKey = ud.string(forKey: Key.volcAppKey.rawValue) ?? ""
        values.volcAccessKey = ud.string(forKey: Key.volcAccessKey.rawValue) ?? ""
        values.volcResourceId = ud.string(forKey: Key.volcResourceId.rawValue) ?? VolcASRModel.recommended.rawValue
        values.qwenASRModel = ud.string(forKey: Key.qwenASRModel.rawValue)
            ?? ud.string(forKey: Key.qwenASRModelPath.rawValue)
            ?? QwenASRModel.defaultID
        values.preloadSpeechModelOnLaunch = ud.object(forKey: Key.preloadSpeechModelOnLaunch.rawValue) as? Bool ?? true
        values.preloadFormattingModelOnLaunch = ud.object(forKey: Key.preloadFormattingModelOnLaunch.rawValue) as? Bool ?? true
        values.modelStoragePath = ud.string(forKey: Key.modelStoragePath.rawValue) ?? DataLocations.models.path
        values.localWhisperModelPaths = ud.dictionary(forKey: Key.localWhisperModelPaths.rawValue) as? [String: String] ?? [:]
        values.localLLMModelPaths = ud.dictionary(forKey: Key.localLLMModelPaths.rawValue) as? [String: String] ?? [:]
        values.developerInterfaceEnabled = ud.object(forKey: Key.developerInterfaceEnabled.rawValue) as? Bool ?? false
        values.developerHTTPPort = validDeveloperHTTPPort(ud.integer(forKey: Key.developerHTTPPort.rawValue))
        if let savedToken = ud.string(forKey: Key.developerHTTPToken.rawValue), !savedToken.isEmpty {
            values.developerHTTPToken = savedToken
        } else {
            let token = generateDeveloperHTTPToken()
            values.developerHTTPToken = token
            ud.set(token, forKey: Key.developerHTTPToken.rawValue)
        }

        return values
    }

    static func validDeveloperHTTPPort(_ port: Int) -> Int {
        (1 ... 65_535).contains(port) ? port : 38_765
    }

}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZeroInt: Int? { self == 0 ? nil : self }
}
