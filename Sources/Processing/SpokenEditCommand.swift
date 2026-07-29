import Foundation

enum SelectionRewriteIntent: Equatable {
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

enum SpokenEditCommand: Equatable {
    case replaceLast(String)
    case replaceSelection(String)
    case rewriteLast(SelectionRewriteIntent)
    case rewriteSelection(SelectionRewriteIntent)
    case deleteSelection
    case undoLastInsertion
}

enum SpokenEditCommandPayloadCleaner {
    static func cleanReplacement(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SpokenEditCommandTargetAvailability {
    case available
    case unavailable
    case unknown

    var chinesePromptDescription: String {
        switch self {
        case .available: return "可用"
        case .unavailable: return "不可用"
        case .unknown: return "未知"
        }
    }

    var englishPromptDescription: String {
        switch self {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .unknown: return "unknown"
        }
    }

    var japanesePromptDescription: String {
        switch self {
        case .available: return "利用可能"
        case .unavailable: return "利用不可"
        case .unknown: return "不明"
        }
    }

    var koreanPromptDescription: String {
        switch self {
        case .available: return "사용 가능"
        case .unavailable: return "사용 불가"
        case .unknown: return "알 수 없음"
        }
    }
}

struct SpokenEditCommandResolutionContext {
    static let previewCharacterLimit = 320
    static let unknown = SpokenEditCommandResolutionContext()

    var lastInsertion: SpokenEditCommandTargetAvailability = .unknown
    var selectedText: SpokenEditCommandTargetAvailability = .unknown
    var lastInsertionPreview: String?
    var selectedTextPreview: String?

    static func preview(_ text: String?, limit: Int = previewCharacterLimit) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }

        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum SpokenEditCommandLLMResolution: Equatable {
    case command(SpokenEditCommand)
    case none
}
