import Foundation

package final class StreamingPreviewAccumulator {
    private static let minimumMeaningfulOverlap = 2
    private static let minimumLatinFuzzyOverlap = 4, minimumLatinContinuationOverlap = 3

    package init() {}

    package private(set) var previewText = ""
    private var latestWindow = ""

    package func merge(_ rawText: String) -> String {
        let windowText = Self.normalize(rawText)
        guard !windowText.isEmpty else { return previewText }
        defer { latestWindow = windowText }

        if previewText.isEmpty {
            previewText = windowText
            return previewText
        }

        if windowText == latestWindow {
            return previewText
        }

        if previewText.hasSuffix(latestWindow) {
            let sharedPrefix = Self.commonPrefixCount(latestWindow, windowText)
            let shortestWindow = min(latestWindow.count, windowText.count)
            let requiredPrefix = max(
                Self.minimumMeaningfulOverlap,
                (shortestWindow * 3 + 3) / 4
            )
            if sharedPrefix >= requiredPrefix {
                previewText.removeLast(latestWindow.count)
                previewText += windowText
                return previewText
            }
        }

        previewText = Self.merge(existing: previewText, incoming: windowText)
        return previewText
    }

    package static func merge(existing: String, incoming: String) -> String {
        let current = normalize(existing)
        let next = normalize(incoming)

        guard !current.isEmpty else { return next }
        guard !next.isEmpty else { return current }

        if current == next || current.hasSuffix(next) || current.contains(next) {
            return current
        }

        if next.hasPrefix(current) {
            return next
        }

        if let fuzzyOverlap = punctuationTolerantOverlap(existing: current, incoming: next) {
            let remainder = String(next.dropFirst(fuzzyOverlap))
            let prefix = removeTentativeTrailingPunctuation(from: current, before: remainder)
            return prefix + remainder
        }

        return join(current, next)
    }

    private static func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func punctuationTolerantOverlap(existing: String, incoming: String) -> Int? {
        let existingUnits = canonicalOverlapUnits(existing)
        let incomingUnits = canonicalOverlapUnits(incoming)
        let maxOverlap = min(existingUnits.count, incomingUnits.count)
        guard maxOverlap >= minimumMeaningfulOverlap else { return nil }

        for count in stride(from: maxOverlap, through: minimumMeaningfulOverlap, by: -1) {
            let existingSuffix = Array(existingUnits.suffix(count))
            let incomingPrefix = Array(incomingUnits.prefix(count))
            if existingSuffix.map(\.value) == incomingPrefix.map(\.value),
               isAcceptableFuzzyOverlap(existingSuffix: existingSuffix, incomingPrefix: incomingPrefix) {
                return incomingPrefix[count - 1].endOffset
            }
        }

        return nil
    }

    private static func isAcceptableFuzzyOverlap(
        existingSuffix: [OverlapUnit],
        incomingPrefix: [OverlapUnit]
    ) -> Bool {
        if existingSuffix.count >= minimumLatinFuzzyOverlap {
            return true
        }
        if existingSuffix.contains(where: \.isNoSpaceScript) {
            return true
        }
        if existingSuffix.count >= minimumLatinContinuationOverlap,
           existingSuffix.first?.startsAtBoundary == true,
           existingSuffix.last?.endsAtBoundary == true,
           incomingPrefix.first?.startsAtBoundary == true,
           incomingPrefix.last?.endsAtBoundary == false {
            return true
        }
        return existingSuffix.first?.startsAtBoundary == true
            && existingSuffix.last?.endsAtBoundary == true
            && incomingPrefix.first?.startsAtBoundary == true
            && incomingPrefix.last?.endsAtBoundary == true
    }

    private static func canonicalOverlapUnits(_ text: String) -> [OverlapUnit] {
        let characters = Array(text)
        return characters.enumerated().compactMap { index, character in
            guard character.isOverlapSignificant else { return nil }
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            return OverlapUnit(
                value: String(character).lowercased(),
                endOffset: index + 1,
                isNoSpaceScript: character.isNoSpaceScript,
                startsAtBoundary: previous?.isOverlapSignificant != true,
                endsAtBoundary: next?.isOverlapSignificant != true
            )
        }
    }

    private static func commonPrefixCount(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    private static func removeTentativeTrailingPunctuation(from current: String, before remainder: String) -> String {
        guard let nextMeaningful = remainder.first(where: \.isOverlapSignificant),
              nextMeaningful.isOverlapSignificant else {
            return current
        }

        var result = current
        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        if result.last?.isTentativeContinuationPunctuation == true {
            result.removeLast()
            return result
        }
        return current
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        guard let lhsLast = lhs.last, let rhsFirst = rhs.first else {
            return lhs + rhs
        }

        if lhsLast.needsSpace(before: rhsFirst) {
            return lhs + " " + rhs
        }

        return lhs + rhs
    }
}

private struct OverlapUnit {
    let value: String
    let endOffset: Int
    let isNoSpaceScript: Bool
    let startsAtBoundary: Bool
    let endsAtBoundary: Bool
}

private extension Character {
    var isOverlapSignificant: Bool {
        !isWhitespace && !unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
    }

    var isLetterOrNumberLike: Bool {
        unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }

    var isNoSpaceScript: Bool {
        unicodeScalars.contains(where: NoSpaceScript.contains)
    }

    var isTentativeContinuationPunctuation: Bool {
        ".。!！?？,，、;；:：".contains(self)
    }

    func needsSpace(before next: Character) -> Bool {
        if isNoSpaceScript || next.isNoSpaceScript {
            return false
        }
        if isLetterOrNumberLike && next.isLetterOrNumberLike {
            return true
        }
        return isTentativeContinuationPunctuation && next.isLetterOrNumberLike
    }
}
