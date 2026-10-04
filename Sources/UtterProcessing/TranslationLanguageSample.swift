import Foundation

package enum TranslationLanguageSample {
    private static let code = try! NSRegularExpression(pattern: #"(?s)```.*?```|`[^`]*`"#)
    private static let identifiers = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])(?:[A-Z]{2,}[A-Z0-9_-]*|[a-z]+[A-Z][A-Za-z0-9]*|[A-Za-z]+_[A-Za-z0-9_]+)(?![\p{L}\p{N}_])"#)

    package static func prepare(_ text: String, knownTerms: [String] = []) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping
        let full = NSRange(normalized.startIndex..., in: normalized)
        let protected = TranscriptFidelityGuard.protectedTokens(in: normalized)
        var ranges = protected.map(\.range)
            + TranscriptFidelityGuard.numberEvents(in: normalized, protectedTokens: protected).map(\.range)
            + code.matches(in: normalized, range: full).map(\.range)
            + identifiers.matches(in: normalized, range: full).map(\.range)
        for term in Set(knownTerms) where !term.isEmpty && normalized.localizedCaseInsensitiveContains(term) {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let expression = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}_])" + escaped + "(?![\\p{L}\\p{N}_])",
                options: .caseInsensitive)
            ranges += expression?.matches(in: normalized, range: full).map(\.range) ?? []
        }
        let sample = NSMutableString(string: normalized)
        for range in ranges {
            sample.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return sample as String
    }

    package static func hasLinguisticContent(_ sample: String) -> Bool {
        let letters = sample.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let nonLatin = letters.filter { $0.value > 0x024F }.count
        if nonLatin >= 4 { return true }
        let words = sample.split { !$0.isLetter }
        return letters.count >= 6 && words.count >= 2
    }
}
