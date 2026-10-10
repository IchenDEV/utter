import Foundation

package enum TextProcessingMode: Equatable, Sendable {
    case direct
    case formatting
    case command
    case translation(TranslationLanguage)
    case selectionEdit(SelectionRewriteIntent, spokenCommand: String)
}

