import Foundation

enum TranslationLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: return L("translation.language.english")
        case .simplifiedChinese: return L("translation.language.chinese_simplified")
        case .traditionalChinese: return L("translation.language.chinese_traditional")
        case .japanese: return L("translation.language.japanese")
        case .korean: return L("translation.language.korean")
        case .spanish: return L("translation.language.spanish")
        case .french: return L("translation.language.french")
        case .german: return L("translation.language.german")
        }
    }

    var promptName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese (zh-Hans)"
        case .traditionalChinese: return "Traditional Chinese (zh-Hant)"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        }
    }
}
