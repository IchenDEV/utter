import Foundation

extension PromptCatalog {
    static func formatContractSection(
        kind: TextFormatKind,
        inputLanguage: InputLanguage
    ) -> String {
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return chineseFormatContract(kind)
        case .english:
            return englishFormatContract(kind)
        case .japanese:
            return japaneseFormatContract(kind)
        case .korean:
            return koreanFormatContract(kind)
        }
    }
}
private extension PromptCatalog {
    static func chineseFormatContract(_ kind: TextFormatKind) -> String {
        let rule: String
        switch kind {
        case .plainParagraph:
            rule = "输出自然段落；只在话题明显切换时换段，不要列点、编号或添加标题。"
        case .unorderedList:
            rule = "输出无序清单；每项独立一行并使用“- ”。只有原文明说标题时才保留标题，绝对不要改成编号步骤。"
        case .orderedSteps:
            rule = "输出有序步骤；每一步独立一行并使用“1. 2. 3.”。保持原文顺序，不新增步骤。"
        case .email:
            rule = "按邮件排版：称呼、正文自然段、结束语、署名之间换行；原文没说的称呼、结束语或署名不得补写。"
        case .chat:
            rule = "按聊天消息排版：短句、短段、自然语气；不要套用邮件格式，不要添加标题。"
        case .codeOrTerminal:
            rule = "按代码或终端文本处理：逐字保护命令、路径、URL、大小写、符号和换行；不要使用智能引号或自然语言列表改写。"
        }
        return """
        本次已判定的输出类型：\(kind.rawValue)。严格遵守对应排版契约，不要自行切换类型：
        - \(rule)
        - 排版只能改变结构和标点，不能增加、删除或改写原文事实。
        """
    }

    static func englishFormatContract(_ kind: TextFormatKind) -> String {
        let rule: String
        switch kind {
        case .plainParagraph:
            rule = "Use natural paragraphs. Break only on a clear topic shift; do not add bullets, numbering, or a heading."
        case .unorderedList:
            rule = "Use an unordered list with one '- ' item per line. Keep a heading only if it was dictated. Never turn the items into numbered steps."
        case .orderedSteps:
            rule = "Use ordered steps with one '1. 2. 3.' item per line. Preserve the dictated order and add no steps."
        case .email:
            rule = "Use email layout with separate greeting, body paragraphs, closing, and signature. Never invent a missing greeting, closing, or signature."
        case .chat:
            rule = "Use compact chat layout with short natural paragraphs. Do not add email conventions or a heading."
        case .codeOrTerminal:
            rule = "Preserve commands, paths, URLs, casing, symbols, and line breaks exactly. Do not use smart quotes or rewrite code as prose."
        }
        return """
        Audited output type for this request: \(kind.rawValue). Follow its contract and do not switch types:
        - \(rule)
        - Formatting may change structure and punctuation only; it must not change the dictated facts.
        """
    }

    static func japaneseFormatContract(_ kind: TextFormatKind) -> String {
        let rules: [TextFormatKind: String] = [
            .plainParagraph: "自然な段落にし、明確な話題転換だけで改段する。箇条書き、番号、見出しを追加しない。",
            .unorderedList: "各項目を「- 」で別行にした番号なしリストにする。口述されていない見出しを追加せず、番号付き手順に変えない。",
            .orderedSteps: "各手順を 1. 2. 3. の別行にする。順序を保ち、手順を追加しない。",
            .email: "挨拶、本文、結び、署名を改行で分ける。口述されていない要素は追加しない。",
            .chat: "短い自然なチャット文にし、メール形式や見出しを追加しない。",
            .codeOrTerminal: "コマンド、パス、URL、大文字小文字、記号、改行を正確に保護する。",
        ]
        return "今回の出力タイプは \(kind.rawValue)。タイプを変更せず、この契約に従う：\(rules[kind] ?? "") 内容の事実は変更しない。"
    }

    static func koreanFormatContract(_ kind: TextFormatKind) -> String {
        let rules: [TextFormatKind: String] = [
            .plainParagraph: "자연스러운 문단으로 쓰고 명확한 주제 전환에서만 줄을 바꾼다. 목록, 번호, 제목을 추가하지 않는다.",
            .unorderedList: "각 항목을 '- '로 시작하는 별도 줄에 쓴다. 말하지 않은 제목을 추가하거나 번호 단계로 바꾸지 않는다.",
            .orderedSteps: "각 단계를 1. 2. 3. 별도 줄에 쓴다. 순서를 유지하고 단계를 추가하지 않는다.",
            .email: "인사말, 본문, 맺음말, 서명을 줄로 구분한다. 말하지 않은 요소는 추가하지 않는다.",
            .chat: "짧고 자연스러운 채팅 문단으로 쓰고 이메일 형식이나 제목을 추가하지 않는다.",
            .codeOrTerminal: "명령어, 경로, URL, 대소문자, 기호, 줄바꿈을 정확히 보존한다.",
        ]
        return "이번 출력 유형은 \(kind.rawValue)이다. 유형을 바꾸지 말고 다음 계약을 따른다: \(rules[kind] ?? "") 받아쓴 사실은 변경하지 않는다."
    }
}
