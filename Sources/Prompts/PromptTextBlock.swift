enum PromptTextBlock {
    /// Uses a deterministic fence that does not occur in the payload. This
    /// preserves dictated text verbatim without letting it close its own block.
    static func block(_ text: String) -> String {
        let index = boundaryIndex(for: text)
        let opening = "<<<OPENTYPE_TEXT_\(index)>>>"
        let closing = "<<<END_OPENTYPE_TEXT_\(index)>>>"
        return """
        \(opening)
        \(text)
        \(closing)
        """
    }

    private static func boundaryIndex(for text: String) -> Int {
        var index = 0
        while text.contains("<<<OPENTYPE_TEXT_\(index)>>>")
            || text.contains("<<<END_OPENTYPE_TEXT_\(index)>>>") {
            index += 1
        }
        return index
    }
}
