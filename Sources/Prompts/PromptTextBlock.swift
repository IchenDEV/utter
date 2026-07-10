enum PromptTextBlock {
    /// Wraps text in `<<< >>>` delimiters for prompts. The content is embedded
    /// verbatim: rewriting delimiters inside user text (e.g. a dictated
    /// "<<<EOF") would corrupt what the model is asked to transcribe, which is
    /// worse than a model occasionally seeing an early `>>>`.
    static func block(_ text: String) -> String {
        """
        <<<
        \(text)
        >>>
        """
    }
}
