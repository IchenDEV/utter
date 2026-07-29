import Foundation

enum VoiceInputMode: Equatable {
    case dictation
    case translation(TranslationLanguage)

    var isTranslation: Bool {
        if case .translation = self { return true }
        return false
    }
}
