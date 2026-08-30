import Foundation

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
        [.qwen3, .whisper, .apple, .volc]
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

enum LocalLLMBackend: String, Codable, CaseIterable {
    case mlx
    case espresso
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
