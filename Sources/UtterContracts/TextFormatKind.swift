import Foundation

package enum TextFormatKind: String, Codable, CaseIterable, Sendable {
    case plainParagraph
    case unorderedList
    case orderedSteps
    case email
    case chat
    case codeOrTerminal
}

package struct TextFormatDecision: Equatable, Sendable {
    package enum Reason: String, Sendable {
        case explicitSequence
        case explicitList
        case emailStructure
        case emailApplication
        case chatApplication
        case codeApplication
        case defaultParagraph
    }

    package let kind: TextFormatKind
    package let reason: Reason

    package init(kind: TextFormatKind, reason: Reason) {
        self.kind = kind
        self.reason = reason
    }
}

