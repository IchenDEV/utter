import Foundation

extension PromptCatalog {
    static func activeIndustryLexiconSection(_ entries: String, inputLanguage: InputLanguage) -> String? {
        let entries = entries.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            医疗行业词库：
            \(PromptTextBlock.block(entries))
            仅在语音原文有直接依据时用于术语拼写和缩写识别；不得据此补写诊断、药名、剂量、数值或医嘱。
            """
        case .english:
            return """
            Medical terminology:
            \(PromptTextBlock.block(entries))
            Use only for terminology spelling and abbreviation recognition supported by the transcript. Never add diagnoses, drugs, doses, measurements, or orders.
            """
        case .japanese:
            return """
            医療用語集：
            \(PromptTextBlock.block(entries))
            音声原文に根拠がある用語表記と略語認識だけに使用し、診断、薬剤、用量、数値、指示を補わないでください。
            """
        case .korean:
            return """
            의료 용어집:
            \(PromptTextBlock.block(entries))
            음성 원문에 근거한 용어 표기와 약어 인식에만 사용하고 진단, 약물, 용량, 수치 또는 지시를 추가하지 마세요.
            """
        }
    }

    static func activePersonalDictionarySection(_ entries: String, inputLanguage: InputLanguage) -> String? {
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

    static func activeEditRulesSection(_ rules: String, inputLanguage: InputLanguage) -> String? {
        let rules = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rules.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            额外编辑规则：
            \(PromptTextBlock.block(rules))
            """
        case .english:
            return """
            Extra edit rules:
            \(PromptTextBlock.block(rules))
            """
        case .japanese:
            return """
            追加編集ルール：
            \(PromptTextBlock.block(rules))
            """
        case .korean:
            return """
            추가 편집 규칙:
            \(PromptTextBlock.block(rules))
            """
        }
    }
}
