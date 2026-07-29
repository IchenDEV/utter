import Foundation

extension TranscriptFidelityGuard {
    static func collapsingRepeatedRangeUnits(
        _ sequence: [String]
    ) -> [String] {
        var collapsed: [String] = []
        var index = 0
        while index < sequence.count {
            if index + 3 < sequence.count,
               sequence[index].hasPrefix("number:"),
               sequence[index + 1].hasPrefix("unit:"),
               sequence[index + 2].hasPrefix("number:"),
               sequence[index + 1] == sequence[index + 3] {
                collapsed.append(sequence[index])
                collapsed.append(sequence[index + 2])
                collapsed.append(sequence[index + 3])
                index += 4
            } else {
                collapsed.append(sequence[index])
                index += 1
            }
        }
        return collapsed
    }

    static func numberSemanticKeys(
        for event: NumberEvent,
        in text: String
    ) -> [String] {
        guard let range = Range(event.range, in: text) else {
            return event.values.map { "number:\($0)" }
        }
        let raw = String(text[range])
        if event.values.count == 3,
           raw.contains("-") || raw.contains("/") {
            let firstDigits = raw.prefix { $0.isNumber }
            if firstDigits.count == 4 {
                let dateUnits = ["year", "month", "day"]
                return zip(event.values, dateUnits).flatMap {
                    ["number:\($0.0)", "unit:\($0.1)"]
                }
            }
        }

        var keys = event.values.map { "number:\($0)" }
        if let unit = measurementUnit(
            before: range.lowerBound,
            after: range.upperBound,
            in: text
        ) {
            keys.append("unit:\(unit)")
        }
        return keys
    }

    private static func measurementUnit(
        before startIndex: String.Index,
        after index: String.Index,
        in text: String
    ) -> String? {
        let prefix = String(text[..<startIndex].suffix(4))
        let currencyPrefixes: [(String, String)] = [
            ("$", "usd"), ("€", "eur"), ("£", "gbp"), ("¥", "yen"),
            ("￥", "yen"),
        ]
        if let match = currencyPrefixes.first(where: {
            prefix.trimmingCharacters(in: .whitespaces).hasSuffix($0.0)
        }) {
            return match.1
        }
        let suffix = String(text[index...].prefix(24))
        let mappings: [(String, String)] = [
            (#"^\s*(?:秒|秒钟|秒鐘)"#, "second"),
            (#"^\s*(?:分钟|分鐘|分)"#, "minute"),
            (#"^\s*(?:小时|小時|时|時)"#, "hour"),
            (#"^\s*(?:天|日)"#, "day"),
            (#"^\s*(?:个月|個月|月)"#, "month"),
            (#"^\s*(?:年)"#, "year"),
            (#"^\s*(?:个|個)"#, "count"),
            (#"^\s*(?:页|頁)"#, "page"),
            (#"^\s*(?:次)"#, "times"),
            (#"^\s*(?:元|块|塊)"#, "currency"),
            (#"^\s*(?:米)"#, "meter"),
            (#"^\s*(?:度)"#, "degree"),
            (#"(?i)^\s*seconds?\b"#, "second"),
            (#"(?i)^\s*minutes?\b"#, "minute"),
            (#"(?i)^\s*hours?\b"#, "hour"),
            (#"(?i)^\s*days?\b"#, "day"),
            (#"(?i)^\s*months?\b"#, "month"),
            (#"(?i)^\s*years?\b"#, "year"),
            (#"(?i)^\s*(?:meters?|metres?)\b"#, "meter"),
            (#"(?i)^\s*degrees?\b"#, "degree"),
            (#"(?i)^\s*(?:dollars?|usd)\b"#, "currency"),
            (#"(?i)^\s*(?:pages?)\b"#, "page"),
            (#"(?i)^\s*(?:times?)\b"#, "times"),
            (#"(?i)^\s*(?:kg|kilograms?)\b"#, "kg"),
            (#"(?i)^\s*(?:lb|lbs|pounds?)\b"#, "lb"),
            (#"(?i)^\s*(?:km|kilometers?|kilometres?)\b"#, "km"),
            (#"(?i)^\s*(?:cm|centimeters?|centimetres?)\b"#, "cm"),
            (#"(?i)^\s*(?:mm|millimeters?|millimetres?)\b"#, "mm"),
            (#"(?i)^\s*(?:ml|milliliters?|millilitres?)\b"#, "ml"),
            (#"(?i)^\s*(?:mb|megabytes?)\b"#, "mb"),
            (#"(?i)^\s*(?:gb|gigabytes?)\b"#, "gb"),
            (#"(?i)^\s*(?:tb|terabytes?)\b"#, "tb"),
            (#"(?i)^\s*(?:°\s*c|celsius)\b"#, "celsius"),
            (#"(?i)^\s*(?:°\s*f|fahrenheit)\b"#, "fahrenheit"),
        ]
        for (pattern, unit) in mappings where suffix.range(
            of: pattern,
            options: .regularExpression
        ) != nil {
            return unit
        }
        return nil
    }
}
