import Foundation

extension TranscriptFidelityGuard {
    private static let clockExpression = try! NSRegularExpression(
        pattern: #"([零〇一二两兩三四五六七八九十\d]+)\s*[点點]\s*([零〇一二两兩三四五六七八九十\d]+)\s*分"#
    )

    static func clockEvents(in text: String, protectedTokens: [ProtectedToken]) -> [NumberEvent] {
        let opaqueRanges = protectedTokens.filter { $0.category != "number" }.map(\.range)
        var events: [NumberEvent] = []
        let range = NSRange(text.startIndex..., in: text)
        for match in clockExpression.matches(in: text, range: range) {
            guard !opaqueRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let hours = Range(match.range(at: 1), in: text),
                  let minutes = Range(match.range(at: 2), in: text),
                  let hour = clockValue(String(text[hours]), limit: 23),
                  let minute = clockValue(String(text[minutes]), limit: 59) else { continue }
            events.append(NumberEvent(range: match.range, values: [hour, minute],
                units: ["clockHour", "minute"]))
        }
        for token in protectedTokens where token.category == "number" {
            guard let range = Range(token.range, in: text) else { continue }
            let components = text[range].split(separator: ":")
            guard components.count == 2,
                  let hour = clockValue(String(components[0]), limit: 23),
                  let minute = clockValue(String(components[1]), limit: 59) else { continue }
            events.append(NumberEvent(range: token.range, values: [hour, minute],
                units: ["clockHour", "minute"]))
        }
        return events
    }

    static func numberKeys(value: String, unit: String, range: Range<String.Index>, in text: String) -> [String] {
        var keys = ["number:\(value)", "unit:\(unit)"]
        if unit == "clockHour" {
            let prefix = String(text[..<range.lowerBound].suffix(12))
            let periods: [(String, String)] = [
                (#"(?:下午|晚上|夜里|夜裡)\s*$"#, "pm"),
                (#"(?:上午|早上|凌晨)\s*$"#, "am"),
                (#"(?:中午)\s*$"#, "noon"),
            ]
            if let period = periods.first(where: {
                prefix.range(of: $0.0, options: .regularExpression) != nil
            }) { keys.append("period:\(period.1)") }
        }
        return keys
    }

    private static func clockValue(_ text: String, limit: Int) -> String? {
        let value = Int(text) ?? chineseNumberValue(text).flatMap(Int.init)
        guard let value, (0...limit).contains(value) else { return nil }
        return String(value)
    }
}
