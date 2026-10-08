import UtterContracts
extension PromptCatalog {
    package static func processingContextSections(
        screenContext: String,
        screenImageAvailable: Bool,
        memoryContext: String,
        inputContext: InputContext? = nil,
        inputLanguage: InputLanguage
    ) -> [String] {
        compactProcessingSections(
            inputTargetContextSection(inputContext, inputLanguage: inputLanguage),
            processingScreenContext(screenContext, inputLanguage: inputLanguage),
            processingScreenImageContext(inputLanguage: inputLanguage, isAvailable: screenImageAvailable),
            processingMemoryContext(memoryContext, inputLanguage: inputLanguage),
            runtimeContextSection(inputLanguage: inputLanguage)
        )
    }
}

private func compactProcessingSections(_ sections: String?...) -> [String] {
    sections.compactMap { $0 }
}

private func processingScreenContext(_ screenContext: String, inputLanguage: InputLanguage) -> String? {
    guard !screenContext.isEmpty else { return nil }
    let label: String
    switch inputLanguage {
    case .auto, .chinese, .cantonese:
        label = "屏幕文字，仅供纠错和专有名词参考，不要混入输出："
    case .english:
        label = "On-screen text for correction and proper nouns only. Do not copy into output:"
    case .japanese:
        label = "画面上のテキスト。誤認識補正と固有名詞の参考だけに使い、出力には混ぜないでください："
    case .korean:
        label = "화면 텍스트입니다. 오인식 보정과 고유명사 참고용으로만 사용하고 출력에 섞지 마세요:"
    }

    return """
    \(label)
    \(PromptTextBlock.block(screenContext))
    """
}

private func processingScreenImageContext(inputLanguage: InputLanguage, isAvailable: Bool) -> String? {
    guard isAvailable else { return nil }
    switch inputLanguage {
    case .auto, .chinese, .cantonese:
        return "屏幕截图已随本次请求提供。请直接观察截图，仅用于纠错、识别专有名词和理解当前上下文，不要把截图内容无关地混入输出。"
    case .english:
        return "A screen image is attached to this request. Inspect it directly for corrections, proper nouns, and current context only. Do not copy unrelated screen content into the output."
    case .japanese:
        return "画面スクリーンショットが添付されています。誤認識補正、固有名詞の識別、現在文脈の理解にだけ使い、無関係な画面内容を出力に混ぜないでください。"
    case .korean:
        return "화면 스크린샷이 첨부되어 있습니다. 오인식 보정, 고유명사 식별, 현재 맥락 이해에만 사용하고 관련 없는 화면 내용을 출력에 섞지 마세요."
    }
}

private func processingMemoryContext(_ memoryContext: String, inputLanguage: InputLanguage) -> String? {
    guard !memoryContext.isEmpty else { return nil }
    let label: String
    switch inputLanguage {
    case .auto, .chinese, .cantonese:
        label = "最近输入，仅供语境、术语、专有名词和语气参考；不要把这里的新事实加入输出："
    case .english:
        label = "Recent input for context, terminology, proper nouns, and tone only. Do not add new facts from it:"
    case .japanese:
        label = "最近の入力。文脈、用語、固有名詞、語調の参考だけに使い、ここから新しい事実を出力に追加しないでください："
    case .korean:
        label = "최근 입력입니다. 맥락, 용어, 고유명사, 어조 참고용으로만 사용하고 여기의 새 사실을 출력에 추가하지 마세요:"
    }

    return """
    \(label)
    \(PromptTextBlock.block(memoryContext))
    """
}
