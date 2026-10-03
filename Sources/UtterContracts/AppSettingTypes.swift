import Foundation

package enum UILanguage: String, Codable, CaseIterable, Sendable {
    case chinese = "zh"
    case english = "en"

    package var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

package enum OutputMode: String, Codable, CaseIterable, Sendable {
    case direct = "direct"
    case processed = "processed"
    case command = "command"

    package var label: String {
        switch self {
        case .direct: return L("mode.verbatim")
        case .processed: return L("mode.smart_format")
        case .command: return L("mode.voice_command")
        }
    }
}

package enum SpeechEngineType: String, Codable, CaseIterable, Sendable {
    case whisper = "whisper"
    case apple = "apple"
    case volc = "volc"
    case qwen3 = "qwen3"
    case firered = "firered"
    case megaASR = "megaASR"

    package static var selectableCases: [SpeechEngineType] {
        [.qwen3, .firered, .megaASR, .whisper, .apple, .volc]
    }

    package var label: String {
        switch self {
        case .whisper: return "WhisperKit"
        case .apple: return L("engine.apple_speech")
        case .volc: return L("engine.volc_asr")
        case .qwen3: return L("engine.qwen3_asr")
        case .firered: return L("engine.firered_asr")
        case .megaASR: return L("engine.mega_asr")
        }
    }

    /// The ASR model ID associated with this engine, if any.
    package var asrModelID: String? {
        switch self {
        case .qwen3: return QwenASRModel.defaultID
        case .firered: return "mlx-community/FireRedASR2-AED-mlx"
        case .megaASR: return "mlx-community/Mega-ASR-6bit"
        default: return nil
        }
    }
}

package enum LocalLLMBackend: String, Codable, CaseIterable, Sendable {
    case mlx
    case espresso
}

package enum LanguageStyle: String, Codable, CaseIterable, Sendable {
    case casual = "casual"
    case professional = "professional"
    case custom = "custom"

    package var label: String {
        switch self {
        case .casual: return L("style.casual")
        case .professional: return L("style.professional")
        case .custom: return L("style.custom")
        }
    }

    package var defaultPrompt: String {
        switch self {
        case .casual: return L("style.prompt.casual")
        case .professional: return L("style.prompt.professional")
        case .custom: return L("style.prompt.custom")
        }
    }

    package var icon: String {
        switch self {
        case .casual: return "bubble.left"
        case .professional: return "list.number"
        case .custom: return "slider.horizontal.3"
        }
    }

    package var usesCustomPrompt: Bool { self == .custom }

    package static func migrated(from savedValue: String) -> LanguageStyle {
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

    package static func looksLikePresetPrompt(_ prompt: String) -> Bool {
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

package enum HotkeyType: String, Codable, CaseIterable, Sendable {
    case ctrl = "Ctrl"
    case shift = "Shift"
    case option = "Option"
    case fn = "Fn"
}

package enum ActivationMode: String, Codable, CaseIterable, Sendable {
    case longPress = "longPress"
    case doubleTap = "doubleTap"
    case toggle = "toggle"

    package var label: String {
        switch self {
        case .longPress: return L("mode.hold_record")
        case .doubleTap: return L("mode.double_tap")
        case .toggle: return L("mode.tap_toggle")
        }
    }
}

package enum HistoryRetention: String, Codable, CaseIterable, Sendable {
    case forever = "forever"
    case threeDays = "threeDays"
    case sevenDays = "sevenDays"
    case oneMonth = "oneMonth"

    package var label: String {
        switch self {
        case .forever: return L("retention.forever")
        case .threeDays: return L("retention.three_days")
        case .sevenDays: return L("retention.seven_days")
        case .oneMonth: return L("retention.one_month")
        }
    }

    package var timeInterval: TimeInterval? {
        switch self {
        case .forever: return nil
        case .threeDays: return 3 * 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .oneMonth: return 30 * 24 * 3600
        }
    }
}

package enum MenuBarIcon: String, Codable, CaseIterable, Sendable {
    case mic = "mic"
    case waveform = "waveform"
    case bubble = "bubble"

    package var symbolName: String {
        switch self {
        case .mic: return "mic.fill"
        case .waveform: return "waveform"
        case .bubble: return "bubble.left.fill"
        }
    }

    package var label: String {
        switch self {
        case .mic: return L("icon.mic")
        case .waveform: return L("icon.waveform")
        case .bubble: return L("icon.bubble")
        }
    }
}

package enum AppIconAppearance: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    package func resourceName(systemIsDark: Bool) -> String {
        switch self {
        case .system: return systemIsDark ? "AppIconDark" : "AppIconLight"
        case .dark: return "AppIconDark"
        case .light: return "AppIconLight"
        }
    }

    package var label: String {
        switch self {
        case .system: return L("app_icon.system")
        case .dark: return L("app_icon.dark")
        case .light: return L("app_icon.light")
        }
    }
}

package enum InputLanguage: String, Codable, CaseIterable, Sendable {
    case auto = "Auto"
    case chinese = "中文"
    case english = "English"
    case japanese = "日本語"
    case korean = "한국어"
    case cantonese = "粤语"

    package var whisperCode: String? {
        switch self {
        case .auto: return nil
        case .chinese: return "zh"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .cantonese: return "yue"
        }
    }

    package var localeIdentifier: String {
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

/// User-facing sensitivity presets for the two independent audio activity
/// threshold groups. `standard` always resolves to the shipped defaults, so
/// existing users keep their behavior until they change the setting.
package enum AudioSensitivity: String, Codable, CaseIterable, Sendable {
    case conservative
    case standard
    case sensitive

    package var label: String { L("settings.sensitivity.\(rawValue)") }

    /// Higher = only louder audio counts as speech.
    package var gateThresholds: AudioActivityThresholds.Gate {
        let base = AudioActivityThresholds.default.gate
        return AudioActivityThresholds.Gate(
            minimumAverageRMS: base.minimumAverageRMS * gateMultiplier,
            minimumPeakRMS: base.minimumPeakRMS * gateMultiplier
        )
    }

    /// Higher = quiet recordings are more readily treated as weak speech.
    package var weakSpeechEvidenceThresholds: AudioActivityThresholds.WeakSpeechEvidence {
        let base = AudioActivityThresholds.default.weakSpeechEvidence
        return AudioActivityThresholds.WeakSpeechEvidence(
            averageRMS: base.averageRMS * weakSpeechMultiplier,
            peakRMS: base.peakRMS * weakSpeechMultiplier
        )
    }

    private var gateMultiplier: Float {
        switch self {
        case .conservative: return 2.0
        case .standard: return 1.0
        case .sensitive: return 0.5
        }
    }

    private var weakSpeechMultiplier: Float {
        switch self {
        case .conservative: return 0.5
        case .standard: return 1.0
        case .sensitive: return 2.0
        }
    }
}
