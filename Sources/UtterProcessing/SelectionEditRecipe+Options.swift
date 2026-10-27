import Foundation
import UtterContracts

extension SelectionEditRecipe {
    package static func selectionEditOptions(for text: String, intent: SelectionRewriteIntent) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let size = selectionEditSize(for: characterCount)

        let maxTokens: Int
        switch intent {
        case .title:
            maxTokens = 96
        case .replyBrief:
            maxTokens = 192
        case .expand, .reply, .replyFormal, .replyFriendly, .replyInEnglish, .replyInChinese,
                .replyAccept, .replyDecline, .replyClarify:
            maxTokens = [384, 768, 1024][size]
        case .meetingNotes:
            maxTokens = [640, 1024, 1536][size]
        case .keyPoints, .decisions, .questions, .risks, .deadlines, .owners, .table,
                .bulletList, .numberedList, .actionItems, .checklist:
            maxTokens = [384, 640, 1024][size]
        case .formal, .casual, .summary, .concise, .proofread, .translateToEnglish, .translateToChinese:
            maxTokens = [256, 512, 768][size]
        case .custom:
            maxTokens = [384, 768, 1280][size]
        }

        let temperature: Double
        switch intent {
        case .keyPoints, .decisions, .questions, .risks, .deadlines, .owners, .proofread,
                .table, .bulletList, .numberedList, .actionItems, .checklist:
            temperature = 0.10
        case .casual, .replyFriendly:
            temperature = 0.18
        case .custom:
            temperature = 0.15
        default:
            temperature = 0.15
        }

        return GenerationOptions(maxTokens: maxTokens, temperature: temperature)
    }

    package static func selectionEditSize(for characterCount: Int) -> Int {
        switch characterCount {
        case 0...120:
            return 0
        case 121...360:
            return 1
        default:
            return 2
        }
    }
}
