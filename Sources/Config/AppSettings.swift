import Foundation
import Combine
import Security

enum UILanguage: String, Codable, CaseIterable {
    case chinese = "zh"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum OutputMode: String, Codable, CaseIterable {
    case direct = "direct"
    case processed = "processed"
    case command = "command"

    var label: String {
        switch self {
        case .direct: return L("mode.verbatim")
        case .processed: return L("mode.smart_format")
        case .command: return L("mode.voice_command")
        }
    }
}

enum SpeechEngineType: String, Codable, CaseIterable {
    case whisper = "whisper"
    case apple = "apple"
    case volc = "volc"
    case qwen3 = "qwen3"
    case mimo = "mimo"

    static var selectableCases: [SpeechEngineType] {
        allCases.filter { $0 != .mimo }
    }

    var label: String {
        switch self {
        case .whisper: return "WhisperKit"
        case .apple: return L("engine.apple_speech")
        case .volc: return L("engine.volc_asr")
        case .qwen3: return L("engine.qwen3_asr")
        case .mimo: return L("engine.mimo_asr")
        }
    }
}

enum LanguageStyle: String, Codable, CaseIterable {
    case casual = "casual"
    case professional = "professional"
    case custom = "custom"

    var label: String {
        switch self {
        case .casual: return L("style.casual")
        case .professional: return L("style.professional")
        case .custom: return L("style.custom")
        }
    }

    var defaultPrompt: String {
        switch self {
        case .casual: return L("style.prompt.casual")
        case .professional: return L("style.prompt.professional")
        case .custom: return L("style.prompt.custom")
        }
    }

    var icon: String {
        switch self {
        case .casual: return "bubble.left"
        case .professional: return "list.number"
        case .custom: return "slider.horizontal.3"
        }
    }

    var usesCustomPrompt: Bool { self == .custom }

    static func migrated(from savedValue: String) -> LanguageStyle {
        if let style = LanguageStyle(rawValue: savedValue) {
            return style
        }

        let normalized = savedValue.lowercased()
        if normalized.contains("casual") || savedValue.contains("口语") {
            return .casual
        }
        if normalized.contains("custom") || savedValue.contains("自定义") {
            return .custom
        }
        if normalized.contains("professional")
            || normalized.contains("formal")
            || normalized.contains("concise")
            || savedValue.contains("专业")
            || savedValue.contains("正式")
            || savedValue.contains("简洁") {
            return .professional
        }
        return .professional
    }

    static func looksLikePresetPrompt(_ prompt: String) -> Bool {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompts = [
            L("style.prompt.casual"),
            L("style.prompt.professional"),
            L("style.prompt.concise"),
            L("style.prompt.formal"),
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return prompts.contains(normalized)
    }
}

enum HotkeyType: String, Codable, CaseIterable {
    case ctrl = "Ctrl"
    case shift = "Shift"
    case option = "Option"
    case fn = "Fn"
}

enum ActivationMode: String, Codable, CaseIterable {
    case longPress = "longPress"
    case doubleTap = "doubleTap"
    case toggle = "toggle"

    var label: String {
        switch self {
        case .longPress: return L("mode.hold_record")
        case .doubleTap: return L("mode.double_tap")
        case .toggle: return L("mode.tap_toggle")
        }
    }
}

enum HistoryRetention: String, Codable, CaseIterable {
    case forever = "forever"
    case threeDays = "threeDays"
    case sevenDays = "sevenDays"
    case oneMonth = "oneMonth"

    var label: String {
        switch self {
        case .forever: return L("retention.forever")
        case .threeDays: return L("retention.three_days")
        case .sevenDays: return L("retention.seven_days")
        case .oneMonth: return L("retention.one_month")
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .forever: return nil
        case .threeDays: return 3 * 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .oneMonth: return 30 * 24 * 3600
        }
    }
}

enum MenuBarIcon: String, Codable, CaseIterable {
    case mic = "mic"
    case waveform = "waveform"
    case bubble = "bubble"

    var symbolName: String {
        switch self {
        case .mic: return "mic.fill"
        case .waveform: return "waveform"
        case .bubble: return "bubble.left.fill"
        }
    }

    var label: String {
        switch self {
        case .mic: return L("icon.mic")
        case .waveform: return L("icon.waveform")
        case .bubble: return L("icon.bubble")
        }
    }
}

enum AppIconAppearance: String, Codable, CaseIterable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    func resourceName(systemIsDark: Bool) -> String {
        switch self {
        case .system: return systemIsDark ? "AppIconDark" : "AppIconLight"
        case .dark: return "AppIconDark"
        case .light: return "AppIconLight"
        }
    }

    var label: String {
        switch self {
        case .system: return L("app_icon.system")
        case .dark: return L("app_icon.dark")
        case .light: return L("app_icon.light")
        }
    }
}

enum InputLanguage: String, Codable, CaseIterable {
    case auto = "Auto"
    case chinese = "中文"
    case english = "English"
    case japanese = "日本語"
    case korean = "한국어"
    case cantonese = "粤语"

    var whisperCode: String? {
        switch self {
        case .auto: return nil
        case .chinese: return "zh"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .cantonese: return "yue"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .auto: return Locale.current.identifier
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .cantonese: return "zh-HK"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let defaultLLMModelID = "mlx-community/Qwen3.5-2B-4bit"

    @Published var hotkeyType: HotkeyType {
        didSet {
            if translationHotkeyModifier == hotkeyType {
                translationHotkeyModifier = Self.defaultTranslationModifier(excluding: hotkeyType)
            }
        }
    }
    @Published var translationHotkeyModifier: HotkeyType {
        didSet {
            if translationHotkeyModifier == hotkeyType {
                translationHotkeyModifier = Self.defaultTranslationModifier(excluding: hotkeyType)
            }
        }
    }
    @Published var activationMode: ActivationMode
    @Published var tapInterval: Double
    @Published var speechEngine: SpeechEngineType
    @Published var whisperModel: String
    @Published var llmModel: String
    @Published var microphoneID: String?
    @Published var outputMode: OutputMode
    @Published var languageStyle: LanguageStyle
    @Published var customStylePrompt: String
    @Published var playSounds: Bool
    @Published var enableStreamingRecognitionBeta: Bool
    @Published var inputLanguage: InputLanguage
    @Published var translationTargetLanguage: TranslationLanguage
    @Published var useScreenContext: Bool
    @Published var screenContextMode: ScreenContextMode
    @Published var enableInstantInsert: Bool
    @Published var hasCompletedOnboarding: Bool
    @Published var uiLanguage: UILanguage {
        didSet { Loc.use(uiLanguage) }
    }
    @Published var historyRetention: HistoryRetention
    @Published var enableMemory: Bool
    @Published var memoryWindowMinutes: Int
    @Published var enableCorrectionLearning: Bool
    @Published var useCustomSystemPrompt: Bool
    @Published var customSystemPrompt: String
    @Published var useRemoteLLM: Bool
    @Published var remoteProvider: RemoteProvider
    @Published var remoteAPIKey: String
    @Published var remoteBaseURL: String
    @Published var remoteModel: String
    @Published var menuBarIcon: MenuBarIcon
    @Published var appIconAppearance: AppIconAppearance
    @Published var volcAppKey: String
    @Published var volcAccessKey: String
    @Published var volcResourceId: String
    @Published var qwenASRModel: String
    @Published var preloadSpeechModelOnLaunch: Bool
    @Published var preloadFormattingModelOnLaunch: Bool
    @Published var modelStoragePath: String
    @Published var localWhisperModelPaths: [String: String]
    @Published var localLLMModelPaths: [String: String]
    @Published var developerInterfaceEnabled: Bool
    @Published var developerHTTPPort: Int
    @Published var developerHTTPToken: String

    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    private enum Key: String {
        case hotkeyType, translationHotkeyModifier, activationMode, tapInterval, speechEngine, whisperModel, llmModel
        case microphoneID, outputMode, languageStyle, customStylePrompt, playSounds
        case enableStreamingRecognitionBeta
        case inputLanguage, translationTargetLanguage
        case useScreenContext, screenContextMode, enableInstantInsert, hasCompletedOnboarding, uiLanguage, historyRetention
        case enableMemory, memoryWindowMinutes, enableCorrectionLearning
        case useCustomSystemPrompt, customSystemPrompt
        case useRemoteLLM, remoteProvider, remoteAPIKey, remoteBaseURL, remoteModel
        case menuBarIcon, appIconAppearance
        case volcAppKey, volcAccessKey, volcResourceId
        case qwenASRModel, qwenASRModelPath
        case preloadSpeechModelOnLaunch, preloadFormattingModelOnLaunch
        case modelStoragePath, localWhisperModelPaths, localLLMModelPaths
        case developerInterfaceEnabled, developerHTTPPort, developerHTTPToken
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let ud = defaults
        let loadedUILanguage = UILanguage(rawValue: ud.string(forKey: Key.uiLanguage.rawValue) ?? "") ?? .chinese
        Loc.use(loadedUILanguage)
        let loadedHotkeyType = HotkeyType(rawValue: ud.string(forKey: Key.hotkeyType.rawValue) ?? "") ?? .fn
        hotkeyType = loadedHotkeyType
        let loadedTranslationModifier = HotkeyType(
            rawValue: ud.string(forKey: Key.translationHotkeyModifier.rawValue) ?? ""
        ) ?? .shift
        translationHotkeyModifier = loadedTranslationModifier == loadedHotkeyType
            ? Self.defaultTranslationModifier(excluding: loadedHotkeyType)
            : loadedTranslationModifier
        let savedMode = ud.string(forKey: Key.activationMode.rawValue) ?? ""
        activationMode = ActivationMode(rawValue: savedMode)
            ?? (savedMode.contains("长按") ? .longPress : savedMode.contains("双击") ? .doubleTap : savedMode.contains("单击") ? .toggle : nil)
            ?? .longPress
        tapInterval = ud.double(forKey: Key.tapInterval.rawValue).nonZero ?? 0.4
        let savedEngine = ud.string(forKey: Key.speechEngine.rawValue) ?? ""
        let loadedSpeechEngine = SpeechEngineType(rawValue: savedEngine)
            ?? (savedEngine.contains("Whisper") || savedEngine.contains("whisper") ? .whisper : nil)
            ?? .apple
        speechEngine = loadedSpeechEngine == .mimo ? .apple : loadedSpeechEngine
        if loadedSpeechEngine == .mimo {
            ud.set(SpeechEngineType.apple.rawValue, forKey: Key.speechEngine.rawValue)
        }
        [
            "localASRPythonPath",
            "mimoASRRepoPath",
            "mimoASRModel",
            "mimoASRModelPath",
            "mimoASRTokenizerPath",
        ].forEach(ud.removeObject(forKey:))
        whisperModel = ud.string(forKey: Key.whisperModel.rawValue) ?? "large-v3"
        llmModel = ud.string(forKey: Key.llmModel.rawValue) ?? Self.defaultLLMModelID
        microphoneID = ud.string(forKey: Key.microphoneID.rawValue)
        let savedOutput = ud.string(forKey: Key.outputMode.rawValue) ?? ""
        outputMode = OutputMode(rawValue: savedOutput)
            ?? (savedOutput.contains("整理") ? .processed : nil)
            ?? .processed
        let savedStyle = ud.string(forKey: Key.languageStyle.rawValue) ?? ""
        let style = LanguageStyle.migrated(from: savedStyle)
        languageStyle = style
        if let savedPrompt = ud.string(forKey: Key.customStylePrompt.rawValue), !savedPrompt.isEmpty {
            customStylePrompt = savedPrompt
        } else {
            customStylePrompt = LanguageStyle.custom.defaultPrompt
        }
        playSounds = ud.object(forKey: Key.playSounds.rawValue) as? Bool ?? true
        enableStreamingRecognitionBeta = ud.object(forKey: Key.enableStreamingRecognitionBeta.rawValue) as? Bool ?? true
        inputLanguage = InputLanguage(rawValue: ud.string(forKey: Key.inputLanguage.rawValue) ?? "") ?? .chinese
        translationTargetLanguage = TranslationLanguage(
            rawValue: ud.string(forKey: Key.translationTargetLanguage.rawValue) ?? ""
        ) ?? .english
        useScreenContext = ud.object(forKey: Key.useScreenContext.rawValue) as? Bool ?? false
        screenContextMode = ScreenContextMode(rawValue: ud.string(forKey: Key.screenContextMode.rawValue) ?? "") ?? .ocr
        enableInstantInsert = ud.object(forKey: Key.enableInstantInsert.rawValue) as? Bool ?? false
        hasCompletedOnboarding = ud.bool(forKey: Key.hasCompletedOnboarding.rawValue)
        uiLanguage = loadedUILanguage
        historyRetention = HistoryRetention(rawValue: ud.string(forKey: Key.historyRetention.rawValue) ?? "") ?? .forever
        enableMemory = ud.object(forKey: Key.enableMemory.rawValue) as? Bool ?? true
        memoryWindowMinutes = (ud.integer(forKey: Key.memoryWindowMinutes.rawValue)).nonZeroInt ?? 30
        enableCorrectionLearning = ud.object(forKey: Key.enableCorrectionLearning.rawValue) as? Bool ?? true
        useCustomSystemPrompt = ud.bool(forKey: Key.useCustomSystemPrompt.rawValue)
        customSystemPrompt = ud.string(forKey: Key.customSystemPrompt.rawValue) ?? ""
        useRemoteLLM = ud.bool(forKey: Key.useRemoteLLM.rawValue)
        remoteProvider = RemoteProvider(rawValue: ud.string(forKey: Key.remoteProvider.rawValue) ?? "") ?? .custom
        remoteAPIKey = ud.string(forKey: Key.remoteAPIKey.rawValue) ?? ""
        remoteBaseURL = ud.string(forKey: Key.remoteBaseURL.rawValue) ?? ""
        remoteModel = ud.string(forKey: Key.remoteModel.rawValue) ?? ""
        menuBarIcon = MenuBarIcon(rawValue: ud.string(forKey: Key.menuBarIcon.rawValue) ?? "") ?? .mic
        appIconAppearance = AppIconAppearance(rawValue: ud.string(forKey: Key.appIconAppearance.rawValue) ?? "") ?? .system
        volcAppKey = ud.string(forKey: Key.volcAppKey.rawValue) ?? ""
        volcAccessKey = ud.string(forKey: Key.volcAccessKey.rawValue) ?? ""
        volcResourceId = ud.string(forKey: Key.volcResourceId.rawValue) ?? VolcASRModel.recommended.rawValue
        qwenASRModel = ud.string(forKey: Key.qwenASRModel.rawValue)
            ?? ud.string(forKey: Key.qwenASRModelPath.rawValue)
            ?? QwenASRModel.defaultID
        preloadSpeechModelOnLaunch = ud.object(forKey: Key.preloadSpeechModelOnLaunch.rawValue) as? Bool ?? true
        preloadFormattingModelOnLaunch = ud.object(forKey: Key.preloadFormattingModelOnLaunch.rawValue) as? Bool ?? true
        modelStoragePath = ud.string(forKey: Key.modelStoragePath.rawValue) ?? ModelStorage.defaultRoot.path
        localWhisperModelPaths = ud.dictionary(forKey: Key.localWhisperModelPaths.rawValue) as? [String: String] ?? [:]
        localLLMModelPaths = ud.dictionary(forKey: Key.localLLMModelPaths.rawValue) as? [String: String] ?? [:]
        developerInterfaceEnabled = ud.object(forKey: Key.developerInterfaceEnabled.rawValue) as? Bool ?? false
        developerHTTPPort = Self.validDeveloperHTTPPort(ud.integer(forKey: Key.developerHTTPPort.rawValue))
        if let savedToken = ud.string(forKey: Key.developerHTTPToken.rawValue), !savedToken.isEmpty {
            developerHTTPToken = savedToken
        } else {
            let token = Self.generateDeveloperHTTPToken()
            developerHTTPToken = token
            ud.set(token, forKey: Key.developerHTTPToken.rawValue)
        }

        setupPersistence()
    }

    private func setupPersistence() {
        $hotkeyType.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.hotkeyType.rawValue) }.store(in: &cancellables)
        $translationHotkeyModifier.dropFirst().sink {
            [defaults] in defaults.set($0.rawValue, forKey: Key.translationHotkeyModifier.rawValue)
        }.store(in: &cancellables)
        $activationMode.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.activationMode.rawValue) }.store(in: &cancellables)
        $tapInterval.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.tapInterval.rawValue) }.store(in: &cancellables)
        $speechEngine.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.speechEngine.rawValue) }.store(in: &cancellables)
        $whisperModel.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.whisperModel.rawValue) }.store(in: &cancellables)
        $llmModel.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.llmModel.rawValue) }.store(in: &cancellables)
        $microphoneID.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.microphoneID.rawValue) }.store(in: &cancellables)
        $outputMode.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.outputMode.rawValue) }.store(in: &cancellables)
        $languageStyle.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.languageStyle.rawValue) }.store(in: &cancellables)
        $customStylePrompt.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.customStylePrompt.rawValue) }.store(in: &cancellables)
        $playSounds.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.playSounds.rawValue) }.store(in: &cancellables)
        $enableStreamingRecognitionBeta.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.enableStreamingRecognitionBeta.rawValue) }.store(in: &cancellables)
        $inputLanguage.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.inputLanguage.rawValue) }.store(in: &cancellables)
        $translationTargetLanguage.dropFirst().sink {
            [defaults] in defaults.set($0.rawValue, forKey: Key.translationTargetLanguage.rawValue)
        }.store(in: &cancellables)
        $useScreenContext.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.useScreenContext.rawValue) }.store(in: &cancellables)
        $screenContextMode.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.screenContextMode.rawValue) }.store(in: &cancellables)
        $enableInstantInsert.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.enableInstantInsert.rawValue) }.store(in: &cancellables)
        $hasCompletedOnboarding.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.hasCompletedOnboarding.rawValue) }.store(in: &cancellables)
        $uiLanguage.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.uiLanguage.rawValue) }.store(in: &cancellables)
        $historyRetention.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.historyRetention.rawValue) }.store(in: &cancellables)
        $enableMemory.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.enableMemory.rawValue) }.store(in: &cancellables)
        $memoryWindowMinutes.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.memoryWindowMinutes.rawValue) }.store(in: &cancellables)
        $enableCorrectionLearning.dropFirst().sink {
            [defaults] in defaults.set($0, forKey: Key.enableCorrectionLearning.rawValue)
        }.store(in: &cancellables)
        $useCustomSystemPrompt.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.useCustomSystemPrompt.rawValue) }.store(in: &cancellables)
        $customSystemPrompt.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.customSystemPrompt.rawValue) }.store(in: &cancellables)
        $useRemoteLLM.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.useRemoteLLM.rawValue) }.store(in: &cancellables)
        $remoteProvider.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.remoteProvider.rawValue) }.store(in: &cancellables)
        $remoteAPIKey.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.remoteAPIKey.rawValue) }.store(in: &cancellables)
        $remoteBaseURL.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.remoteBaseURL.rawValue) }.store(in: &cancellables)
        $remoteModel.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.remoteModel.rawValue) }.store(in: &cancellables)
        $menuBarIcon.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.menuBarIcon.rawValue) }.store(in: &cancellables)
        $appIconAppearance.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.appIconAppearance.rawValue) }.store(in: &cancellables)
        $volcAppKey.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.volcAppKey.rawValue) }.store(in: &cancellables)
        $volcAccessKey.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.volcAccessKey.rawValue) }.store(in: &cancellables)
        $volcResourceId.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.volcResourceId.rawValue) }.store(in: &cancellables)
        $qwenASRModel.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.qwenASRModel.rawValue) }.store(in: &cancellables)
        $preloadSpeechModelOnLaunch.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.preloadSpeechModelOnLaunch.rawValue) }.store(in: &cancellables)
        $preloadFormattingModelOnLaunch.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.preloadFormattingModelOnLaunch.rawValue) }.store(in: &cancellables)
        $modelStoragePath.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.modelStoragePath.rawValue) }.store(in: &cancellables)
        $localWhisperModelPaths.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.localWhisperModelPaths.rawValue) }.store(in: &cancellables)
        $localLLMModelPaths.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.localLLMModelPaths.rawValue) }.store(in: &cancellables)
        $developerInterfaceEnabled.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.developerInterfaceEnabled.rawValue) }.store(in: &cancellables)
        $developerHTTPPort.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.developerHTTPPort.rawValue) }.store(in: &cancellables)
        $developerHTTPToken.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.developerHTTPToken.rawValue) }.store(in: &cancellables)
    }

    func resetDeveloperHTTPToken() {
        developerHTTPToken = Self.generateDeveloperHTTPToken()
    }

    private static func generateDeveloperHTTPToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        return Data(bytes).base64EncodedString()
    }

    private static func validDeveloperHTTPPort(_ port: Int) -> Int {
        (1 ... 65_535).contains(port) ? port : 38_765
    }

    private static func defaultTranslationModifier(excluding hotkey: HotkeyType) -> HotkeyType {
        hotkey == .shift ? .option : .shift
    }

    var zh: Bool { uiLanguage == .chinese }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZeroInt: Int? { self == 0 ? nil : self }
}
