import Foundation

package struct SettingsValues: Equatable, Sendable {
    package static let defaultLLMModelID = "mlx-community/Qwen3.5-2B-4bit"
    package static let defaultRemoteMicGainDB: Double = 12

    package var hotkeyType: HotkeyType = .fn {
        didSet {
            if translationHotkeyModifier == hotkeyType {
                translationHotkeyModifier = Self.defaultTranslationModifier(excluding: hotkeyType)
            }
        }
    }
    package var translationHotkeyModifier: HotkeyType = .shift {
        didSet {
            if translationHotkeyModifier == hotkeyType {
                translationHotkeyModifier = Self.defaultTranslationModifier(excluding: hotkeyType)
            }
        }
    }
    package var activationMode: ActivationMode = .longPress
    package var tapInterval: Double = 0.4
    package var speechEngine: SpeechEngineType = .apple
    package var whisperModel: String = "large-v3"
    package var llmModel: String = Self.defaultLLMModelID
    package var microphoneID: String? = nil
    package var remoteMicEnabled: Bool = false
    package var remoteMicGainDB: Double = Self.defaultRemoteMicGainDB
    package var audioGateSensitivity: AudioSensitivity = .standard
    package var audioWeakSpeechSensitivity: AudioSensitivity = .standard
    package var outputMode: OutputMode = .processed
    package var languageStyle: LanguageStyle = .professional
    package var customStylePrompt: String = LanguageStyle.custom.defaultPrompt
    package var playSounds: Bool = true
    package var enableStreamingRecognitionBeta: Bool = true
    package var inputLanguage: InputLanguage = .chinese
    package var translationTargetLanguage: TranslationLanguage = .english
    package var useScreenContext: Bool = false
    package var screenContextMode: ScreenContextMode = .ocr
    package var enableInstantInsert: Bool = false
    package var hasCompletedOnboarding: Bool = false
    package var uiLanguage: UILanguage = .chinese
    package var historyRetention: HistoryRetention = .forever
    package var enableMemory: Bool = true
    package var memoryWindowMinutes: Int = 30
    package var enableCorrectionLearning: Bool = true
    package var industryLexicon: IndustryLexiconID = .general
    package var useCustomSystemPrompt: Bool = false
    package var customSystemPrompt: String = ""
    package var useRemoteLLM: Bool = false
    package var localLLMBackend: LocalLLMBackend = .mlx
    package var espressoModelPath: String = ""
    package var fallbackToMLXOnEspressoFailure: Bool = true
    package var remoteProvider: RemoteProvider = .custom
    package var remoteAPIKey: String = ""
    package var remoteBaseURL: String = ""
    package var remoteModel: String = ""
    package var menuBarIcon: MenuBarIcon = .mic
    package var appIconAppearance: AppIconAppearance = .system
    package var volcAppKey: String = ""
    package var volcAccessKey: String = ""
    package var volcResourceId: String = VolcASRModel.recommended.rawValue
    package var qwenASRModel: String = QwenASRModel.defaultID
    package var preloadSpeechModelOnLaunch: Bool = true
    package var preloadFormattingModelOnLaunch: Bool = true
    package var modelStoragePath: String = DataLocations.models.path
    package var localWhisperModelPaths: [String: String] = [:]
    package var localLLMModelPaths: [String: String] = [:]
    package var developerInterfaceEnabled: Bool = false
    package var developerHTTPPort: Int = 38_765
    package var developerHTTPToken: String = ""

    package init() {}

    package var audioActivityThresholds: AudioActivityThresholds {
        AudioActivityThresholds(gate: audioGateSensitivity.gateThresholds,
            weakSpeechEvidence: audioWeakSpeechSensitivity.weakSpeechEvidenceThresholds).clamped
    }

    package var zh: Bool { uiLanguage == .chinese }

    package static func defaultTranslationModifier(excluding hotkey: HotkeyType) -> HotkeyType {
        hotkey == .shift ? .option : .shift
    }
}
