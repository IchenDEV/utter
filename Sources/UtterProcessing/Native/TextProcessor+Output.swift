import UtterContracts
import Foundation

extension TextProcessor {
    package func stripThinkingTags(_ text: String) -> String {
        GeneratedOutputNormalizer.stripThinkingTags(text)
    }

    package func formattingOptions(for text: String, style: LanguageStyle) -> GenerationOptions {
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
    package func cleanGeneratedOutput(
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
    package func cleanCommandGeneratedOutput(
        _ text: String,
        inputLanguage: InputLanguage
    ) -> String {
        return GeneratedOutputNormalizer.commandText(text)
    }

    package func validatedOutput(
        _ candidate: String,
        source: String,
        protectedTerms: [String] = [],
        inputLanguage: InputLanguage,
        enforceSemanticFidelity: Bool = true
    ) -> String {
        let violation = TranscriptFidelityGuard.violation(
            source: source, candidate: candidate, protectedTerms: protectedTerms,
            inputLanguage: inputLanguage, enforceSemanticFidelity: enforceSemanticFidelity
        )
        ProcessingObservations.current?.record(source: source, candidate: candidate,
            decision: ProcessingDecision(violation == nil ? .accepted : .fallback, reason: violation))
        guard let violation else { return candidate }
        log.error("[TextProcessor] rejected formatting output: \(violation); keeping source transcript")
        return source
    }

    /// Keeps line breaks while collapsing surrounding whitespace.
    package func normalizeWhitespace(_ text: String) -> String {
        TranscriptionSanitizer.normalizeInput(text)
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
