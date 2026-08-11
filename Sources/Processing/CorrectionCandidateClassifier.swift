import Foundation

struct CorrectionEditDiff: Equatable, Sendable {
    let beforeSegment: String
    let afterSegment: String
    let commonPrefixCount: Int
    let commonSuffixCount: Int

    static func between(_ before: String, _ after: String) -> CorrectionEditDiff? {
        guard before != after else { return nil }
        let beforeCharacters = Array(before)
        let afterCharacters = Array(after)
        let sharedLimit = min(beforeCharacters.count, afterCharacters.count)

        var prefix = 0
        while prefix < sharedLimit, beforeCharacters[prefix] == afterCharacters[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < sharedLimit - prefix,
              beforeCharacters[beforeCharacters.count - suffix - 1]
                == afterCharacters[afterCharacters.count - suffix - 1] {
            suffix += 1
        }

        return CorrectionEditDiff(
            beforeSegment: String(beforeCharacters[prefix..<(beforeCharacters.count - suffix)]),
            afterSegment: String(afterCharacters[prefix..<(afterCharacters.count - suffix)]),
            commonPrefixCount: prefix,
            commonSuffixCount: suffix
        )
    }
}

enum CorrectionObservationPolicy {
    static func associatedFinalText(inserted: String, edited: String) -> String? {
        guard let diff = CorrectionEditDiff.between(inserted, edited) else { return nil }
        let insertedCount = inserted.count
        let editedCount = edited.count
        guard editedCount > 0,
              editedCount <= max(256, insertedCount * 3),
              diff.beforeSegment.count + diff.afterSegment.count <= max(64, insertedCount) else {
            return nil
        }

        let isAppend = diff.beforeSegment.isEmpty
            && diff.commonPrefixCount == insertedCount
            && diff.commonSuffixCount == 0
        let isPrepend = diff.beforeSegment.isEmpty
            && diff.commonPrefixCount == 0
            && diff.commonSuffixCount == insertedCount
        guard !isAppend, !isPrepend else { return nil }
        return edited
    }
}

enum CorrectionCandidateClassifier {
    static func candidate(
        inserted: String,
        userFinal: String,
        sourceRecordID: UUID,
        languageCode: String?,
        bundleIdentifier: String?
    ) -> LearnedCorrectionCandidate? {
        guard let diff = CorrectionEditDiff.between(inserted, userFinal) else { return nil }
        var original = diff.beforeSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        var replacement = diff.afterSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else { return nil }

        if containsASCIIWord(original) || containsASCIIWord(replacement) {
            let expanded = expandedASCIISegments(
                before: inserted,
                after: userFinal,
                prefixCount: diff.commonPrefixCount,
                suffixCount: diff.commonSuffixCount
            )
            original = expanded.before.trimmingCharacters(in: .whitespacesAndNewlines)
            replacement = expanded.after.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard isEligibleTerm(original), isEligibleTerm(replacement) else { return nil }
        let originalLexical = lexicalForm(original)
        let replacementLexical = lexicalForm(replacement)
        guard !originalLexical.isEmpty,
              !replacementLexical.isEmpty,
              originalLexical != replacementLexical else {
            return nil
        }

        let caseOrSpacingOnly = originalLexical.lowercased() == replacementLexical.lowercased()
        let hasMultipleHunks = hasMeaningfulSharedInterior(
            diff.beforeSegment,
            diff.afterSegment
        )
        guard caseOrSpacingOnly || !hasMultipleHunks else {
            return nil
        }
        guard !isCommonFunctionWord(original), !isCommonFunctionWord(replacement) else { return nil }

        return LearnedCorrectionCandidate(
            original: original,
            replacement: replacement,
            confidence: confidence(for: replacement, caseOrSpacingOnly: caseOrSpacingOnly),
            sourceRecordID: sourceRecordID,
            languageCode: languageCode,
            bundleIdentifier: bundleIdentifier
        )
    }
}

private extension CorrectionCandidateClassifier {
    static let commonWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
        "he", "her", "his", "i", "in", "is", "it", "me", "my", "of", "on", "or",
        "she", "that", "the", "their", "they", "this", "to", "we", "with", "you", "your",
        "的", "了", "和", "是", "我", "你", "他", "她", "它", "在", "有", "就", "也", "都",
        "而", "及", "与", "着", "或", "一个", "这个", "那个",
    ]

    static func isEligibleTerm(_ text: String) -> Bool {
        let wordCount = text.split { $0.isWhitespace || $0.isPunctuation }.count
        guard text.count <= 48,
              wordCount <= 4,
              !text.contains("\n"),
              !text.contains("\r"),
              !text.allSatisfy({ $0.isNumber || $0.isWhitespace || $0.isPunctuation }),
              !containsSensitivePattern(text) else {
            return false
        }
        return true
    }

    static func containsSensitivePattern(_ text: String) -> Bool {
        let patterns = [
            #"(?i)https?://|www\."#,
            #"\b[^\s@]+@[^\s@]+\.[^\s@]+\b"#,
            #"(?:^|\s)(?:/|~/|\\)[^\s]+"#,
            #"(?i)\b(?:api[_-]?key|token|password|secret|bearer)\b"#,
            #"\b[A-Fa-f0-9]{24,}\b"#,
        ]
        return patterns.contains {
            text.range(of: $0, options: .regularExpression) != nil
        }
    }

    static func isCommonFunctionWord(_ text: String) -> Bool {
        commonWords.contains(text.lowercased())
    }

    static func lexicalForm(_ text: String) -> String {
        String(text.filter { $0.isLetter || $0.isNumber })
    }

    static func containsASCIIWord(_ text: String) -> Bool {
        text.contains { $0.isASCIIWord }
    }

    static func expandedASCIISegments(
        before: String,
        after: String,
        prefixCount: Int,
        suffixCount: Int
    ) -> (before: String, after: String) {
        let beforeCharacters = Array(before)
        let afterCharacters = Array(after)
        let beforeRange = expandedASCIIWordRange(
            in: beforeCharacters,
            start: prefixCount,
            end: beforeCharacters.count - suffixCount
        )
        let afterRange = expandedASCIIWordRange(
            in: afterCharacters,
            start: prefixCount,
            end: afterCharacters.count - suffixCount
        )
        return (
            String(beforeCharacters[beforeRange]),
            String(afterCharacters[afterRange])
        )
    }

    static func expandedASCIIWordRange(
        in characters: [Character],
        start requestedStart: Int,
        end requestedEnd: Int
    ) -> Range<Int> {
        var start = max(0, min(requestedStart, characters.count))
        var end = max(start, min(requestedEnd, characters.count))
        while start > 0, characters[start - 1].isASCIIWord { start -= 1 }
        while end < characters.count, characters[end].isASCIIWord { end += 1 }
        return start..<end
    }

    static func hasMeaningfulSharedInterior(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.lowercased())
        let right = Array(rhs.lowercased())
        guard left.count >= 2, right.count >= 2 else { return false }
        for start in left.indices {
            guard start + 1 < left.count else { continue }
            let pair = String(left[start...start + 1])
            if pair.allSatisfy({ $0.isLetter || $0.isNumber }), rhs.lowercased().contains(pair) {
                return true
            }
        }
        return false
    }

    static func confidence(for replacement: String, caseOrSpacingOnly: Bool) -> Double {
        if caseOrSpacingOnly { return 0.98 }
        let letters = replacement.filter(\.isLetter)
        let hasUppercase = letters.contains(where: { $0.isUppercase })
        let hasLowercase = letters.contains(where: { $0.isLowercase })
        let isAcronym = letters.count >= 2 && letters.allSatisfy(\.isUppercase)
        let isCamelCase = hasUppercase && hasLowercase && !replacement.contains(" ")
        let hasMixedDigits = replacement.contains(where: \.isNumber) && !letters.isEmpty
        return isAcronym || isCamelCase || hasMixedDigits ? 0.95 : 0.82
    }
}
