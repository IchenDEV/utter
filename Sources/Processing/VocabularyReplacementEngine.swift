import Foundation

struct VocabularyReplacementRule: Equatable, Sendable {
    let original: String
    let replacement: String
    let sourcePriority: Int
    let insertionOrder: Int
}

enum VocabularyReplacementEngine {
    static func apply(_ rules: [VocabularyReplacementRule], to text: String) -> String {
        let rankedRules = rules.sorted {
            if $0.original.count != $1.original.count {
                return $0.original.count > $1.original.count
            }
            if $0.sourcePriority != $1.sourcePriority {
                return $0.sourcePriority < $1.sourcePriority
            }
            return $0.insertionOrder < $1.insertionOrder
        }
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

        if let first = original.first, isASCIIWord(first),
           start > text.startIndex,
           isASCIIWord(text[text.index(before: start)]) {
            return false
        }
        if let last = original.last, isASCIIWord(last),
           end < text.endIndex,
           isASCIIWord(text[end]) {
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
