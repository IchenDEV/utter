import Foundation

package enum SelectionRewriteIntent: Equatable, Sendable {
    case formal
    case casual
    case expand
    case title
    case keyPoints
    case decisions
    case questions
    case risks
    case deadlines
    case owners
    case meetingNotes
    case reply
    case replyBrief
    case replyFormal
    case replyFriendly
    case replyInEnglish
    case replyInChinese
    case replyAccept
    case replyDecline
    case replyClarify
    case summary
    case concise
    case proofread
    case table
    case bulletList
    case numberedList
    case actionItems
    case checklist
    case translateToEnglish
    case translateToChinese
    case custom(String)
}

package enum SpokenEditCommand: Equatable, Sendable {
    case replaceLast(String)
    case replaceSelection(String)
    case rewriteLast(SelectionRewriteIntent)
    case rewriteSelection(SelectionRewriteIntent)
    case deleteSelection
    case undoLastInsertion
}

package enum SpokenEditCommandPayloadCleaner {
    package static func cleanReplacement(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

package enum SpokenEditCommandTargetAvailability: Sendable {
    case available
    case unavailable
    case unknown

    package var chinesePromptDescription: String {
        switch self {
        case .available: return "可用"
        case .unavailable: return "不可用"
        case .unknown: return "未知"
        }
    }

    package var englishPromptDescription: String {
        switch self {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .unknown: return "unknown"
        }
    }

    package var japanesePromptDescription: String {
        switch self {
        case .available: return "利用可能"
        case .unavailable: return "利用不可"
        case .unknown: return "不明"
        }
    }

    package var koreanPromptDescription: String {
        switch self {
        case .available: return "사용 가능"
        case .unavailable: return "사용 불가"
        case .unknown: return "알 수 없음"
        }
    }
}

package struct SpokenEditCommandResolutionContext: Sendable {
    package static let previewCharacterLimit = 320
    package static let unknown = SpokenEditCommandResolutionContext()

    package var lastInsertion: SpokenEditCommandTargetAvailability = .unknown
    package var selectedText: SpokenEditCommandTargetAvailability = .unknown
    package var lastInsertionPreview: String?
    package var selectedTextPreview: String?

    package init(
        lastInsertion: SpokenEditCommandTargetAvailability = .unknown,
        selectedText: SpokenEditCommandTargetAvailability = .unknown,
        lastInsertionPreview: String? = nil,
        selectedTextPreview: String? = nil
    ) {
        self.lastInsertion = lastInsertion
        self.selectedText = selectedText
        self.lastInsertionPreview = lastInsertionPreview
        self.selectedTextPreview = selectedTextPreview
    }

    package static func preview(_ text: String?, limit: Int = previewCharacterLimit) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }

        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

package enum SpokenEditCommandLLMResolution: Equatable, Sendable {
    case command(SpokenEditCommand)
    case none
}
