extension PromptCatalog {
    static func asrQualityRules(inputLanguage: InputLanguage) -> String {
        switch inputLanguage {
        case .auto:
            return """
            ASR 质量规则：
            - 主动处理模型幻听和模板尾巴，例如“谢谢观看”“感谢观看”“字幕由...提供”或 "thank you for watching"；只有它和当前口述明显无关时才删除
            - 口述控制词要按意图处理：逗号、句号、问号、换行、空格、不要空格、大写、全大写、引号、冒号；如果用户是在讨论这些词本身，就保留字面
            - 技术词、产品词和缩写优先按常见写法输出，例如 OpenType、hotkey、menu bar、API、JSON、i18n、URL
            - 屏幕、历史和词库只用于纠错和术语选择；不要补出原文没有说出的动作、结论、数值或承诺
            """
        case .chinese:
            return """
            ASR 质量规则：
            - 主动处理模型幻听和模板尾巴，例如“谢谢观看”“感谢观看”“字幕由...提供”；只有它和当前口述明显无关时才删除
            - 口述控制词要按意图处理：逗号、句号、问号、换行、空格、不要空格、大写、全大写、引号、冒号；如果用户是在讨论这些词本身，就保留字面
            - 技术词、产品词和缩写优先按常见写法输出，例如 OpenType、hotkey、menu bar、API、JSON、i18n、URL
            - 屏幕、历史和词库只用于纠错和术语选择；不要补出原文没有说出的动作、结论、数值或承诺
            """
        case .cantonese:
            return """
            ASR 质量规则：
            - 主动处理模型幻听和模板尾巴，例如“谢谢观看”“感谢观看”“字幕由...提供”；只有它同当前口述明显无关时先删除
            - 口述控制词要按意图处理：逗号、句号、问号、换行、空格、唔要空格、大写、全大写、引号、冒号；如果用户是在讨论这些词本身，就保留字面
            - 技术词、产品词和缩写优先按常见写法输出，例如 OpenType、hotkey、menu bar、API、JSON、i18n、URL
            - 屏幕、历史和词库只用于纠错和术语选择；不要补出原文没有说出的动作、结论、数值或承诺
            """
        case .english:
            return """
            ASR quality rules:
            - Remove obvious model hallucinations or template tails such as "thank you for watching", "thanks for watching", or "subtitles by ..." only when they are unrelated to the dictated content
            - Interpret spoken controls by intent: comma, period, question mark, new line, space, no space, caps, all caps, quote, colon; keep them literal when the user is talking about the words themselves
            - Prefer standard spelling for product names, technical terms, and acronyms, such as OpenType, hotkey, menu bar, API, JSON, i18n, and URL
            - Use screen context, history, and dictionary only for corrections and terminology; do not add undictated actions, conclusions, numbers, or commitments
            """
        case .japanese:
            return """
            ASR 品質ルール：
            - 「thank you for watching」「字幕由...提供」のような明らかな幻聴やテンプレート末尾は、口述内容と無関係な場合だけ削除する
            - 口述された制御語は意図として扱う：句読点、改行、スペース、スペースなし、大文字、引用符、コロン。ただしその語自体を話題にしている場合は字面を残す
            - 製品名、技術語、略語は OpenType、hotkey、menu bar、API、JSON、i18n、URL のような標準表記を優先する
            - 画面、履歴、辞書は補正と用語選択にだけ使い、口述されていない動作、結論、数値、約束を追加しない
            """
        case .korean:
            return """
            ASR 품질 규칙:
            - "thank you for watching", "subtitles by ..." 같은 명백한 모델 환청이나 템플릿 꼬리는 받아쓰기 내용과 무관할 때만 제거한다
            - 말로 지시한 제어어는 의도로 처리한다: 쉼표, 마침표, 물음표, 줄바꿈, 공백, 공백 없음, 대문자, 모두 대문자, 따옴표, 콜론. 그 단어 자체를 말하는 경우에는 그대로 둔다
            - 제품명, 기술 용어, 약어는 OpenType, hotkey, menu bar, API, JSON, i18n, URL 같은 표준 표기를 우선한다
            - 화면, 기록, 사전은 보정과 용어 선택에만 사용하고 말하지 않은 동작, 결론, 숫자, 약속을 추가하지 않는다
            """
        }
    }
}
