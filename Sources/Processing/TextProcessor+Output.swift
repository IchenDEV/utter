import Foundation

extension TextProcessor {
    private static let thinkTagNames = [
        "analysis",
        "think", "thinking", "thought",
        "reason", "reasoning",
        "reflect", "reflection",
        "inner_monologue", "scratchpad",
    ]

    private static let thinkTagPattern: String = {
        let names = thinkTagNames.joined(separator: "|")
        return "<(?:\(names))(?:\\s+[^>]*)?>"
    }()

    func stripThinkingTags(_ text: String) -> String {
        if let finalText = LLMScaffoldedOutput.finalText(from: text) {
            return finalText
        }

        var result = text
        for tag in Self.thinkTagNames {
            result = result.replacingOccurrences(
                of: "<\(tag)(?:\\s+[^>]*)?>[\\s\\S]*?</\(tag)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(
            of: "\(Self.thinkTagPattern)[\\s\\S]*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func formattingOptions(for text: String, style: LanguageStyle) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count

        let minimumTokens: Int
        switch (style, characterCount) {
        case (.professional, 0...80), (.custom, 0...80):
            minimumTokens = 224
        case (.professional, 81...220), (.custom, 81...220):
            minimumTokens = 384
        case (.professional, _), (.custom, _):
            minimumTokens = 640
        case (.casual, 0...80):
            minimumTokens = 160
        case (.casual, 81...220):
            minimumTokens = 256
        case (.casual, _):
            minimumTokens = 384
        }

        // CJK transcripts can approach one token per character. Leave enough
        // room for punctuation and formatting without letting requests grow
        // beyond the supported generation ceiling.
        let estimatedTokens = min(characterCount, 2_048) * 2
        let maxTokens = min(4_096, max(minimumTokens, estimatedTokens))

        return GenerationOptions(
            maxTokens: maxTokens,
            temperature: 0
        )
    }

    /// Dictionary replacements are applied once on the input side. Applying
    /// them again could double-expand replacements that contain the original.
    func cleanGeneratedOutput(
        _ text: String,
        inputLanguage: InputLanguage,
        fallback: String = ""
    ) -> String {
        var result = stripThinkingTags(text)
        result = FormattedOutputCleaner.clean(result)
        if result.isEmpty { return FormattedOutputCleaner.clean(fallback) }
        return result
    }

    /// Command output is entirely model-generated, so parsing its advertised
    /// final_text envelope cannot swallow dictated content.
    func cleanCommandGeneratedOutput(
        _ text: String,
        inputLanguage: InputLanguage
    ) -> String {
        let stripped = stripThinkingTags(text)
        if let finalText = LLMFinalTextOutput.text(from: stripped) {
            return FormattedOutputCleaner.clean(finalText)
        }
        return cleanGeneratedOutput(text, inputLanguage: inputLanguage)
    }

    func rejectedOutputFallback(
        _ cleanedText: String,
        allowsGuardFallback: Bool
    ) -> String {
        allowsGuardFallback ? cleanedText : ""
    }

    /// Keeps line breaks while collapsing surrounding whitespace.
    func normalizeWhitespace(_ text: String) -> String {
        FormattingHeuristics.normalizeInput(text)
            .replacingOccurrences(
                of: "[^\\S\\n]*\\n[^\\S\\n]*",
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "[^\\S\\n]+",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\n{3,}",
                with: "\n\n",
                options: .regularExpression
            )
    }
}
