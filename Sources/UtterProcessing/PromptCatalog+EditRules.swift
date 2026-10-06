import UtterContracts
import Foundation

extension PromptCatalog {
    package static func activePersonalDictionarySection(_ entries: String, inputLanguage: InputLanguage) -> String? {
        let entries = entries.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            个人词库：
            \(PromptTextBlock.block(entries))
            """
        case .english:
            return """
            Personal dictionary:
            \(PromptTextBlock.block(entries))
            """
        case .japanese:
            return """
            個人辞書：
            \(PromptTextBlock.block(entries))
            """
        case .korean:
            return """
            개인 사전:
            \(PromptTextBlock.block(entries))
            """
        }
    }

    package static func activeEditRulesSection(_ rules: String, inputLanguage: InputLanguage) -> String? {
        let rules = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rules.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            以下额外编辑规则是用户的明确指令，必须逐条遵守，优先于风格默认写法：
            额外编辑规则：
            \(PromptTextBlock.block(rules))
            """
        case .english:
            return """
            The extra edit rules below are explicit user instructions: follow every one and let them override default style:
            Extra edit rules:
            \(PromptTextBlock.block(rules))
            """
        case .japanese:
            return """
            以下の追加編集ルールはユーザーの明示的な指示です。すべて守り、既定のスタイルより優先してください：
            追加編集ルール：
            \(PromptTextBlock.block(rules))
            """
        case .korean:
            return """
            아래 추가 편집 규칙은 사용자의 명시적 지시이므로 모두 지키고 기본 스타일보다 우선하세요:
            추가 편집 규칙:
            \(PromptTextBlock.block(rules))
            """
        }
    }
}
