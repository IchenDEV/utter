import Foundation

struct VocabularyReplacementRule: Equatable, Sendable {
    let original: String
    let replacement: String
    let sourcePriority: Int
    let insertionOrder: Int
}

enum VocabularyReplacementEngine {
    /// Applies rules left to right with maximum munch at each position:
    ///
    /// - Rules are ranked by longest `original` first, then lower
    ///   `sourcePriority` (personal before industry), then insertion order.
    /// - The first — hence longest — matching rule wins at a position, and the
    ///   cursor advances past the whole match, so replacements never overlap.
    /// - A match may not be glued to an ASCII word character on either side.
    ///   Pure ASCII rules keep their previous boundary behavior, while CJK-only
    ///   and mixed entries (e.g. "Wi-Fi密码") get the same validation, so a
    ///   short CJK term no longer rewrites the CJK tail of an identifier.
    static func apply(_ rules: [VocabularyReplacementRule], to text: String) -> String {
        let rankedRules = rank(rules)
        guard !rankedRules.isEmpty, !text.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if let match = rankedRules.first(where: {
                matches($0.original, in: text, at: cursor)
            }) {
                result += match.replacement
                cursor = text.index(cursor, offsetBy: match.original.count)
            } else {
                result.append(text[cursor])
                cursor = text.index(after: cursor)
            }
        }
        return result
    }

    private static func rank(_ rules: [VocabularyReplacementRule]) -> [VocabularyReplacementRule] {
        rules
            .filter { !$0.original.isEmpty }
            .sorted {
                if $0.original.count != $1.original.count {
                    return $0.original.count > $1.original.count
                }
                if $0.sourcePriority != $1.sourcePriority {
                    return $0.sourcePriority < $1.sourcePriority
                }
                return $0.insertionOrder < $1.insertionOrder
            }
    }

    private static func matches(
        _ original: String,
        in text: String,
        at start: String.Index
    ) -> Bool {
        guard let end = text.index(start, offsetBy: original.count, limitedBy: text.endIndex),
              String(text[start..<end]).compare(
                  original,
                  options: .caseInsensitive
              ) == .orderedSame else {
            return false
        }

        if start > text.startIndex, isASCIIWord(text[text.index(before: start)]) {
            return false
        }
        if end < text.endIndex, isASCIIWord(text[end]) {
            return false
        }
        return true
    }

    private static func isASCIIWord(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else {
            return false
        }
        return (48...57).contains(value)
            || (65...90).contains(value)
            || value == 95
            || (97...122).contains(value)
    }
}
