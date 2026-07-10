extension PromptCatalog {
    static func inputTargetContextSection(_ context: InputContext?, inputLanguage: InputLanguage) -> String? {
        guard let context else { return nil }
        let details = inputTargetDetails(context, inputLanguage: inputLanguage)
        guard !details.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            当前输入目标和光标上下文，仅用于判断语气、专有名词、应用场景、句子承接、代词、省略、大小写和标点；不要把这些元信息或未口述的上下文写入输出：
            \(details)
            """
        case .english:
            return """
            Current input target and cursor context for tone, proper nouns, app context, sentence continuation, pronoun references, ellipses, casing, and punctuation only. Do not copy this metadata or undictated surrounding text into the output:
            \(details)
            """
        case .japanese:
            return """
            現在の入力先とカーソル周辺の文脈。語調、固有名詞、アプリ文脈、文の続き、代名詞、省略、大文字小文字、句読点の判断にだけ使い、このメタ情報や口述されていない周辺テキストを出力に書かないでください：
            \(details)
            """
        case .korean:
            return """
            현재 입력 대상과 커서 주변 맥락입니다. 어조, 고유명사, 앱 맥락, 문장 이어짐, 대명사, 생략, 대소문자, 문장 부호 판단에만 사용하고 이 메타정보나 받아쓰지 않은 주변 텍스트를 출력에 쓰지 마세요:
            \(details)
            """
        }
    }
}

private func inputTargetDetails(_ context: InputContext, inputLanguage: InputLanguage) -> String {
    let metadataLabels: [(String, String?)]
    let focusedTextLabels: [(String, String?)]
    switch inputLanguage {
    case .auto, .chinese, .cantonese:
        metadataLabels = [
            ("应用", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("窗口", context.windowTitle),
        ]
        focusedTextLabels = [
            ("光标前文本", context.textBeforeSelection),
            ("当前选中文本", context.selectedText),
            ("光标后文本", context.textAfterSelection),
        ]
    case .english:
        metadataLabels = [
            ("App", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("Window", context.windowTitle),
        ]
        focusedTextLabels = [
            ("Text before cursor/selection", context.textBeforeSelection),
            ("Selected text", context.selectedText),
            ("Text after cursor/selection", context.textAfterSelection),
        ]
    case .japanese:
        metadataLabels = [
            ("アプリ", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("ウィンドウ", context.windowTitle),
        ]
        focusedTextLabels = [
            ("カーソル前のテキスト", context.textBeforeSelection),
            ("選択中のテキスト", context.selectedText),
            ("カーソル後のテキスト", context.textAfterSelection),
        ]
    case .korean:
        metadataLabels = [
            ("앱", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("창", context.windowTitle),
        ]
        focusedTextLabels = [
            ("커서 앞 텍스트", context.textBeforeSelection),
            ("선택된 텍스트", context.selectedText),
            ("커서 뒤 텍스트", context.textAfterSelection),
        ]
    }

    let metadata: [String] = metadataLabels
        .compactMap { label, value -> String? in
            guard let value else { return nil }
            return "- \(label): \(value)"
        }
    let focusedText: [String] = focusedTextLabels
        .compactMap { label, value -> String? in
            guard let value else { return nil }
            return "- \(label):\n\(PromptTextBlock.block(value))"
        }
    return (metadata + focusedText)
        .joined(separator: "\n")
}
