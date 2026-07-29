import Foundation

extension TranscriptFidelityGuard {
    struct Matcher: @unchecked Sendable {
        let category: String
        let expression: NSRegularExpression
        let captureGroup: Int
    }

    struct ProtectedToken {
        let category: String
        let key: String
        let range: NSRange
    }

    static let alwaysTrailingPunctuation = CharacterSet(
        charactersIn: ".,;:!?，。；：！？"
    )

    static let matchers: [Matcher] = [
        matcher("url", #"(?i)\b(?:https?://|www\.)[^\s<>"']+"#),
        matcher(
            "email",
            #"(?i)(?<![\p{L}\p{N}_.+-])[\p{L}\p{N}.!#$%&'*+/=?^_`{|}~-]+@(?:[\p{L}\p{N}-]+\.)+(?:[\p{L}]{2,}|xn--[a-z0-9-]+)(?![\p{L}\p{N}_-])"#
        ),
        matcher(
            "path",
            #""(?:~|\.\.?|/|[A-Za-z]:\\|\\\\)[^"\r\n]+""#
        ),
        matcher(
            "path",
            #"'(?:~|\.\.?|/|[A-Za-z]:\\|\\\\)[^'\r\n]+'"#
        ),
        matcher(
            "path",
            #"(?<![A-Za-z0-9_])(?:~|\.\.?|/)[^,;!?，。；！？<>\r\n"']*?\.[A-Za-z0-9]{1,16}(?=$|[\s,;!?，。；！？)\]}])"#
        ),
        matcher(
            "path",
            #"(?<![A-Za-z0-9_])(?:~|\.\.?|/)(?:[^\s,;!?，。；！？<>\r\n"']+/)*[^\s,;!?，。；！？<>\r\n"']+"#
        ),
        matcher(
            "path",
            #"(?i)(?<![A-Za-z0-9_])[a-z]:\\(?:[^\\\s]+\\)*[^\\\s]+"#
        ),
        matcher(
            "path",
            #"\\\\[^\\\s]+\\(?:[^\\\s]+\\)*[^\\\s]+"#
        ),
        matcher(
            "path",
            #"(?<![\w./-])(?:[A-Za-z0-9_][A-Za-z0-9._-]*/)+[A-Za-z0-9_][A-Za-z0-9._-]*\.[A-Za-z][A-Za-z0-9]{0,15}(?=$|[\s,;!?，。；！？)\]}])"#
        ),
        matcher(
            "path",
            #"(?<![\w./-])[A-Za-z0-9_][A-Za-z0-9._-]*\.[A-Za-z][A-Za-z0-9]{0,15}(?=$|[\s,;!?，。；！？)\]}])"#
        ),
        matcher("number", #"[+-]?\d+(?:[.,:/-]\d+)*(?:[%％])?"#),
    ]

    static func matcher(
        _ category: String,
        _ pattern: String,
        captureGroup: Int = 0
    ) -> Matcher {
        Matcher(
            category: category,
            expression: try! NSRegularExpression(pattern: pattern),
            captureGroup: captureGroup
        )
    }

    static func protectedTokens(in text: String) -> [ProtectedToken] {
        let normalized = text.precomposedStringWithCanonicalMapping
        let fullRange = NSRange(normalized.startIndex..., in: normalized)
        var occupied: [NSRange] = []
        var tokens: [ProtectedToken] = []

        for matcher in matchers {
            for match in matcher.expression.matches(in: normalized, range: fullRange) {
                let range = match.range(at: matcher.captureGroup)
                guard range.location != NSNotFound,
                      !occupied.contains(where: {
                          NSIntersectionRange($0, range).length > 0
                      }),
                      let swiftRange = Range(range, in: normalized) else {
                    continue
                }
                let rawValue = String(normalized[swiftRange])
                let trimmedValue = trimmingUnbalancedTrailingPunctuation(
                    from: rawValue
                )
                let value = matcher.category == "number"
                    ? trimmedValue.precomposedStringWithCompatibilityMapping
                    : trimmedValue
                guard !value.isEmpty else { continue }
                tokens.append(ProtectedToken(
                    category: matcher.category,
                    key: "\(matcher.category):\(value)",
                    range: range
                ))
                occupied.append(range)
            }
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    static func trimmingUnbalancedTrailingPunctuation(
        from rawValue: String
    ) -> String {
        var value = rawValue
        while let last = value.last {
            if String(last).rangeOfCharacter(
                from: alwaysTrailingPunctuation
            ) != nil {
                value.removeLast()
                continue
            }
            let pair: (open: Character, close: Character)?
            switch last {
            case ")": pair = ("(", ")")
            case "）": pair = ("（", "）")
            case "]": pair = ("[", "]")
            case "】": pair = ("【", "】")
            case "}": pair = ("{", "}")
            default: pair = nil
            }
            guard let pair else { break }
            let opens = value.filter { $0 == pair.open }.count
            let closes = value.filter { $0 == pair.close }.count
            guard closes > opens else { break }
            value.removeLast()
        }
        return value
    }

    static func protectedTokensAreFaithful(
        source: String,
        candidate: String
    ) -> Bool {
        let candidateSequence = protectedSemanticSequence(in: candidate)
        if protectedSemanticSequence(in: source) == candidateSequence {
            return true
        }
        let correctedSource = removingCorrectedNumberEvidence(from: source)
        return correctedSource != source
            && protectedSemanticSequence(in: correctedSource) == candidateSequence
    }

    static func protectedTokensAreBoundedTransformation(
        source: String,
        candidate: String
    ) -> Bool {
        var sourceSequence = protectedSemanticSequence(in: source)[...]
        for token in protectedSemanticSequence(in: candidate) {
            guard let match = sourceSequence.firstIndex(of: token) else {
                return false
            }
            sourceSequence = sourceSequence[sourceSequence.index(after: match)...]
        }
        return true
    }

    static func removingCorrectedNumberEvidence(from text: String) -> String {
        let number = #"(?:[+-]?\d+(?:[.,:/-]\d+)*(?:[%％])?|(?:第|百分之)?[零〇一二两兩三四五六七八九十百千万萬亿億兆]+(?:[点點][零〇一二两兩三四五六七八九]+)?|\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|first|second|third)\b)"#
        let marker = #"(?:不对|講錯咗|说错了|sorry|i mean|correction)"#
        let pattern = "(?i)\(number)\\s*[，,]?\\s*\(marker)\\s*[，,]?\\s*"
        var range = NSRange(text.startIndex..., in: text)
        var result = (try! NSRegularExpression(pattern: pattern))
            .stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: ""
            )
        let contrastPattern =
            "(?:唔係|不是)(?:星期|禮拜|周)?\\s*\(number)\\s*[，,]?\\s*(?:係|是)"
        range = NSRange(result.startIndex..., in: result)
        result = (try! NSRegularExpression(pattern: contrastPattern))
            .stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: ""
            )
        return result
    }
}
