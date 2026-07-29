import Foundation

extension TranscriptFidelityGuard {
    struct NumberEvent {
        let range: NSRange
        let values: [String]
    }

    static let chineseSpokenNumber = try! NSRegularExpression(
        pattern: #"(?:第|百分之)?(?:负|負)?[零〇一二两兩三四五六七八九十百千万萬亿億兆]+(?:[点點][零〇一二两兩三四五六七八九]+)?"#
    )
    static let englishSpokenNumber = try! NSRegularExpression(
        pattern: #"(?i)\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|first|second|third|half|quarter)(?:[\s-]+(?:and[\s-]+)?(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|first|second|third|point))*\b"#
    )
    static let koreanOrdinalNumber = try! NSRegularExpression(
        pattern: #"(?:첫째|둘째|셋째|넷째|다섯째|여섯째|일곱째|여덟째|아홉째|열째)"#
    )

    static func protectedSemanticSequence(in text: String) -> [String] {
        let normalized = text.precomposedStringWithCanonicalMapping
        let protected = protectedTokens(in: normalized)
        var events: [(range: NSRange, values: [String])] = protected
            .filter { $0.category != "number" }
            .map { ($0.range, [$0.key]) }
        events += numberEvents(in: normalized, protectedTokens: protected)
            .map { event in
                (
                    event.range,
                    numberSemanticKeys(for: event, in: normalized)
                )
            }
        let sequence = events
            .sorted { lhs, rhs in
                if lhs.range.location != rhs.range.location {
                    return lhs.range.location < rhs.range.location
                }
                return lhs.range.length > rhs.range.length
            }
            .flatMap(\.values)
        return collapsingRepeatedRangeUnits(sequence)
    }

    static func numericSemanticValues(in text: String) -> [String] {
        let normalized = text.precomposedStringWithCanonicalMapping
        return numberEvents(
            in: normalized,
            protectedTokens: protectedTokens(in: normalized)
        )
        .sorted { $0.range.location < $1.range.location }
        .flatMap(\.values)
    }

    static func numberEvents(
        in text: String,
        protectedTokens: [ProtectedToken]
    ) -> [NumberEvent] {
        var events = protectedTokens
            .filter { $0.category == "number" }
            .compactMap { token -> NumberEvent? in
                guard let range = Range(token.range, in: text) else { return nil }
                let raw = String(text[range])
                let previousCharacter = range.lowerBound > text.startIndex
                    ? text[text.index(before: range.lowerBound)] : nil
                let values = arabicNumberValues(
                    raw,
                    previousCharacter: previousCharacter
                )
                return values.isEmpty ? nil : NumberEvent(
                    range: token.range,
                    values: values
                )
            }
        let occupied = protectedTokens.map(\.range)
        let fullRange = NSRange(text.startIndex..., in: text)

        for match in chineseSpokenNumber.matches(in: text, range: fullRange) {
            guard !overlaps(match.range, occupied),
                  let range = Range(match.range, in: text),
                  var value = chineseNumberValue(String(text[range])) else {
                continue
            }
            let raw = String(text[range])
            let suffix = String(text[range.upperBound...].prefix(4))
            guard isPlausibleChineseNumberEvidence(
                raw: raw,
                range: range,
                text: text
            ) else {
                continue
            }
            if raw == "万一" || raw == "萬一"
                || ((raw == "千万" || raw == "千萬")
                    && suffix.range(
                        of: #"^(?:不要|别|別|勿|不能|唔好)"#,
                        options: .regularExpression
                    ) != nil) {
                continue
            }
            if !value.hasSuffix("%") {
                let prefix = String(text[..<range.lowerBound])
                if prefix.range(
                    of: #"百分之[零〇一二两兩三四五六七八九十百千万萬亿億兆]+(?:到|至)$"#,
                    options: .regularExpression
                ) != nil {
                    value += "%"
                }
            }
            events.append(NumberEvent(range: match.range, values: [value]))
        }
        for match in englishSpokenNumber.matches(in: text, range: fullRange) {
            guard !overlaps(match.range, occupied),
                  let range = Range(match.range, in: text),
                  let value = englishNumberValue(String(text[range])) else {
                continue
            }
            events.append(NumberEvent(range: match.range, values: [value]))
        }
        for match in koreanOrdinalNumber.matches(in: text, range: fullRange) {
            guard !overlaps(match.range, occupied),
                  let range = Range(match.range, in: text),
                  let value = koreanOrdinalValue(String(text[range])) else {
                continue
            }
            events.append(NumberEvent(range: match.range, values: [value]))
        }
        return events
    }

    static func removingRecognizedNumberEvidence(from text: String) -> String {
        var normalized = text.precomposedStringWithCanonicalMapping
        let protected = protectedTokens(in: normalized)
        let ranges = numberEvents(in: normalized, protectedTokens: protected)
            .map(\.range)
            .sorted { $0.location > $1.location }
        for range in ranges {
            guard let swiftRange = Range(range, in: normalized) else { continue }
            normalized.replaceSubrange(swiftRange, with: " ")
        }
        return normalized
    }

    private static func isPlausibleChineseNumberEvidence(
        raw: String,
        range: Range<String.Index>,
        text: String
    ) -> Bool {
        if raw.hasPrefix("第") || raw.hasPrefix("百分之")
            || raw.contains("点") || raw.contains("點") {
            return true
        }
        if raw.count > 1 { return true }

        let prefix = String(text[..<range.lowerBound].suffix(4))
        if prefix.range(
            of: #"(?:周|星期|禮拜|礼拜)$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let suffix = String(text[range.upperBound...].prefix(6))
        return suffix.range(
            of: #"^(?:个|個|天|日|月|年|秒(?:钟|鐘)?|分钟|分鐘|小时|小時|步|页|頁|次|元|块|塊|米|度|岁|歲|歳)"#,
            options: .regularExpression
        ) != nil
            || prefix.hasSuffix("到")
            || prefix.hasSuffix("至")
            || suffix.hasPrefix("到")
            || suffix.hasPrefix("至")
    }

    private static func overlaps(_ range: NSRange, _ occupied: [NSRange]) -> Bool {
        occupied.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func arabicNumberValues(
        _ rawValue: String,
        previousCharacter: Character?
    ) -> [String] {
        var raw = rawValue
            .replacingOccurrences(of: "％", with: "%")
            .precomposedStringWithCompatibilityMapping
        let hasPercent = raw.hasSuffix("%")
        if hasPercent { raw.removeLast() }
        var sign = ""
        if raw.first == "+" || raw.first == "-" {
            if raw.first == "-",
               previousCharacter?.isNumber == true || previousCharacter == "%" ||
                previousCharacter == "％" {
                raw.removeFirst()
            } else {
                sign = String(raw.removeFirst())
            }
        }
        let components = raw.split(
            whereSeparator: { $0 == "-" || $0 == "/" || $0 == ":" }
        )
        guard !components.isEmpty else { return [] }
        let looksLikeDate = components.count == 3
            && components[0].count == 4
        return components.enumerated().compactMap { index, component in
            canonicalDecimal(
                (index == 0 ? sign : "") + component,
                normalizeLeadingZeros: looksLikeDate
            )
            .map { value in
                hasPercent ? value + "%" : value
            }
        }
    }

}
