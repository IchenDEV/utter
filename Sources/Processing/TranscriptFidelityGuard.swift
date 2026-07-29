import Foundation

enum TranscriptFidelityGuard {
    static func violation(
        source: String,
        candidate: String,
        protectedTerms: [String],
        inputLanguage: InputLanguage,
        enforceSemanticFidelity: Bool
    ) -> String? {
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "empty_output"
        }
        let tokensAreSafe = enforceSemanticFidelity
            ? protectedTokensAreFaithful(source: source, candidate: candidate)
            : protectedTokensAreBoundedTransformation(
                source: source,
                candidate: candidate
            )
        guard tokensAreSafe else {
            return "protected_token_change"
        }
        let sourceTerms = protectedTermCounts(in: source, terms: protectedTerms)
        let candidateTerms = protectedTermCounts(in: candidate, terms: protectedTerms)
        let termsAreSafe = enforceSemanticFidelity
            ? sourceTerms == candidateTerms
            : candidateTerms.allSatisfy { sourceTerms[$0.key, default: 0] >= $0.value }
        guard termsAreSafe else {
            return "dictionary_term_change"
        }
        if enforceSemanticFidelity {
            guard polaritySignatures(in: source, language: inputLanguage)
                == polaritySignatures(in: candidate, language: inputLanguage) else {
                return "polarity_change"
            }
            if let violation = contentFidelityViolation(
                source: source,
                candidate: candidate
            ) {
                return violation
            }
        }
        return nil
    }
}

extension TranscriptFidelityGuard {
    static func protectedTermCounts(
        in text: String,
        terms: [String]
    ) -> [String: Int] {
        let normalized = text.precomposedStringWithCanonicalMapping
        let fullRange = NSRange(normalized.startIndex..., in: normalized)
        var counts: [String: Int] = [:]
        for term in terms {
            let normalizedTerm = term.precomposedStringWithCanonicalMapping
            guard !normalizedTerm.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: normalizedTerm)
            let left = normalizedTerm.first?.isASCIIWord == true
                ? "(?<![A-Za-z0-9_])" : ""
            let right = normalizedTerm.last?.isASCIIWord == true
                ? "(?![A-Za-z0-9_])" : ""
            let expression = try! NSRegularExpression(
                pattern: left + escaped + right
            )
            let count = expression.numberOfMatches(in: normalized, range: fullRange)
            if count > 0 { counts[normalizedTerm] = count }
        }
        return counts
    }

    static func polaritySignatures(
        in text: String,
        language: InputLanguage
    ) -> [String: Int] {
        let sanitized = removingSelfCorrectionNegation(
            from: text.precomposedStringWithCompatibilityMapping,
            language: language
        )
        let patterns = polarityPatterns(language: language)
        let range = NSRange(sanitized.startIndex..., in: sanitized)
        var signatures: [String: Int] = [:]
        for pattern in patterns {
            let expression = try! NSRegularExpression(pattern: pattern)
            for match in expression.matches(in: sanitized, range: range) {
                let end = match.range.location + match.range.length
                let suffixRange = NSRange(
                    location: end,
                    length: max(0, range.length - end)
                )
                let suffix = Range(suffixRange, in: sanitized)
                    .map { String(sanitized[$0]) } ?? ""
                let anchor = contentUnits(
                    removingDisfluencyMarkers(from: suffix)
                )
                .prefix(2)
                .joined(separator: "/")
                signatures["neg:\(anchor)", default: 0] += 1
            }
        }
        return signatures
    }

    static func polarityPatterns(language: InputLanguage) -> [String] {
        switch language {
        case .chinese, .cantonese:
            return [chinesePolarityPattern]
        case .english:
            return [englishPolarityPattern]
        case .japanese:
            return [japanesePolarityPattern]
        case .korean:
            return [koreanPolarityPattern]
        case .auto:
            return [
                chinesePolarityPattern,
                englishPolarityPattern,
                japanesePolarityPattern,
                koreanPolarityPattern,
            ]
        }
    }

    static func removingSelfCorrectionNegation(
        from text: String,
        language: InputLanguage
    ) -> String {
        let patterns: [String]
        switch language {
        case .chinese, .cantonese:
            patterns = chineseSelfCorrectionPatterns
        case .english:
            patterns = englishSelfCorrectionPatterns
        case .japanese:
            patterns = japaneseSelfCorrectionPatterns
        case .korean:
            patterns = koreanSelfCorrectionPatterns
        case .auto:
            patterns = chineseSelfCorrectionPatterns
                + englishSelfCorrectionPatterns
                + japaneseSelfCorrectionPatterns
                + koreanSelfCorrectionPatterns
        }
        return patterns.reduce(text) { result, pattern in
            let range = NSRange(result.startIndex..., in: result)
            return (try! NSRegularExpression(pattern: pattern))
                .stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: ""
                )
        }
    }

    static let chineseSelfCorrectionPatterns = [
        "不对",
        "不是(?=.{0,40}(?:而是|改成|应该是))",
        "(?:没有|没)(?=.{0,40}(?:应该有|改成有))",
        "唔係(?=.{0,40}(?:係|改做|應該係))",
        "冇(?=.{0,40}(?:應該有|改做有))",
    ]
    static let englishSelfCorrectionPatterns = [
        #"(?i)\b(?:no|not)\b(?=.{0,50}\b(?:sorry|rather|i mean|correction)\b)"#,
        #"(?i)n['’]t(?=.{0,50}\b(?:sorry|rather|i mean|correction)\b)"#,
    ]
    static let japaneseSelfCorrectionPatterns = [
        "(?:ではない|じゃない)(?=.{0,40}(?:訂正|ではなく|じゃなく))",
    ]
    static let koreanSelfCorrectionPatterns = ["아니(?=고)"]

    static let chinesePolarityPattern =
        "(?:不同意|不赞成|不能|不要|不会|不是|没有|从未|无需|无法|别|勿|唔(?:係|好|會|能|要)?|冇|不(?!对|同|仅|过|管)|没(?!关系)|未(?!来)|无(?!线|论|数))"
    static let englishPolarityPattern =
        #"(?i)(?:\bno\b(?!\s*\.\s*\d)|\b(?:not|never|without|cannot|neither|nor|hardly)\b|n['’]t\b)"#
    static let japanesePolarityPattern =
        "(?:ではない|じゃない|できない|ません|(?<!危|少)ない|ぬ|ず)"
    static let koreanPolarityPattern = "(?:않|못|아니(?!면|고)|없)"
}
