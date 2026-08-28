import Foundation

extension PromptCatalog {
    static func activeIndustryLexiconSection(
        _ terms: String,
        industry: IndustryLexiconID?,
        inputLanguage: InputLanguage
    ) -> String? {
        let terms = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let industry, industry != .general, !terms.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            \(chineseName(for: industry))行业词库，仅用于纠正语音中明确出现的术语；不要据此补充原文没有的信息：
            \(PromptTextBlock.block(terms))
            """
        case .english:
            return """
            \(englishName(for: industry)) industry vocabulary. Use it only to correct terms clearly present in the speech; do not add facts from this list:
            \(PromptTextBlock.block(terms))
            """
        case .japanese:
            return """
            \(englishName(for: industry))業界用語集。音声に明確に含まれる用語の訂正だけに使い、この一覧から情報を追加しないでください：
            \(PromptTextBlock.block(terms))
            """
        case .korean:
            return """
            \(englishName(for: industry)) 업계 용어집입니다. 음성에 명확히 포함된 용어를 교정할 때만 사용하고 목록의 정보를 추가하지 마세요:
            \(PromptTextBlock.block(terms))
            """
        }
    }

    private static func chineseName(for industry: IndustryLexiconID) -> String {
        switch industry {
        case .general: return "通用"
        case .medical: return "医疗"
        case .legal: return "法律"
        case .finance: return "金融财会"
        case .technology: return "软件技术"
        }
    }

    private static func englishName(for industry: IndustryLexiconID) -> String {
        switch industry {
        case .general: return "General"
        case .medical: return "Medical"
        case .legal: return "Legal"
        case .finance: return "Finance and accounting"
        case .technology: return "Software technology"
        }
    }
}
