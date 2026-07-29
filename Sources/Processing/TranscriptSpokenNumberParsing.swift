import Foundation

extension TranscriptFidelityGuard {
    static func canonicalDecimal(
        _ rawValue: String,
        normalizeLeadingZeros: Bool
    ) -> String? {
        var raw = rawValue
        let sign: String
        if raw.first == "+" || raw.first == "-" {
            sign = String(raw.removeFirst())
        } else {
            sign = ""
        }
        if raw.range(
            of: #"^\d{1,3}(?:,\d{3})+$"#,
            options: .regularExpression
        ) != nil {
            raw.removeAll { $0 == "," }
        } else if !raw.contains(".") {
            raw = raw.replacingOccurrences(of: ",", with: ".")
        }
        let pieces = raw.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard pieces.count <= 2,
              let integer = pieces.first,
              integer.allSatisfy(\.isNumber) else {
            return nil
        }
        let normalizedInteger = normalizeLeadingZeros
            ? integer.drop(while: { $0 == "0" }) : integer[...]
        var value = normalizedInteger.isEmpty ? "0" : String(normalizedInteger)
        if pieces.count == 2 {
            guard pieces[1].allSatisfy(\.isNumber) else { return nil }
            value += "." + pieces[1]
        }
        return sign + value
    }

    static func chineseNumberValue(_ rawValue: String) -> String? {
        var raw = rawValue
        let hasPercent = raw.hasPrefix("百分之")
        for prefix in ["第", "百分之"] where raw.hasPrefix(prefix) {
            raw.removeFirst(prefix.count)
        }
        let isNegative = raw.first == "负" || raw.first == "負"
        if isNegative { raw.removeFirst() }
        let decimalParts = raw.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "点" || $0 == "點" }
        )
        guard decimalParts.count <= 2,
              let integer = chineseIntegerValue(String(decimalParts[0])) else {
            return nil
        }
        var value = String(integer)
        if decimalParts.count == 2 {
            let digits = decimalParts[1].compactMap(chineseDigit).map(String.init)
            guard digits.count == decimalParts[1].count else { return nil }
            value += "." + digits.joined()
        }
        if isNegative { value = "-" + value }
        if hasPercent { value += "%" }
        return value
    }

    static func chineseIntegerValue(_ raw: String) -> Int? {
        guard !raw.isEmpty else { return nil }
        let smallUnits: [Character: Int] = [
            "十": 10, "百": 100, "千": 1_000,
        ]
        let largeUnits: [Character: Int] = [
            "万": 10_000, "萬": 10_000, "亿": 100_000_000,
            "億": 100_000_000, "兆": 1_000_000_000_000,
        ]
        if !raw.contains(where: {
            smallUnits[$0] != nil || largeUnits[$0] != nil
        }) {
            let digits = raw.compactMap(chineseDigit).map(String.init)
            return digits.count == raw.count ? Int(digits.joined()) : nil
        }
        var total = 0
        var section = 0
        var digit: Int?
        for character in raw {
            if let value = chineseDigit(character) {
                digit = value
            } else if let unit = smallUnits[character] {
                section += (digit ?? 1) * unit
                digit = nil
            } else if let unit = largeUnits[character] {
                section += digit ?? 0
                total += max(1, section) * unit
                section = 0
                digit = nil
            } else {
                return nil
            }
        }
        return total + section + (digit ?? 0)
    }

    static func chineseDigit(_ character: Character) -> Int? {
        [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "兩": 2,
            "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8,
            "九": 9,
        ][character]
    }

    static func englishNumberValue(_ rawValue: String) -> String? {
        let values = englishCardinalValues
        let words = rawValue.lowercased().split { $0 == " " || $0 == "-" }
        if words == ["half"] { return "0.5" }
        if words == ["quarter"] { return "0.25" }
        if let point = words.firstIndex(of: "point") {
            let leftWords = Array(words[..<point])
            let rightWords = words[words.index(after: point)...]
            guard let integer = englishIntegerValue(
                leftWords,
                values: values
            ), !rightWords.isEmpty else {
                return nil
            }
            let fraction = rightWords.compactMap {
                englishDigitWords[String($0)]
            }
            return fraction.count == rightWords.count
                ? "\(integer)." + fraction.joined() : nil
        }
        if words.count > 1,
           words.allSatisfy({ englishDigitWords[String($0)] != nil }) {
            return words.compactMap {
                englishDigitWords[String($0)]
            }
            .joined()
        }
        if words.count >= 3,
           let first = values[String(words[0])],
           (10..<100).contains(first),
           let remainder = englishIntegerValue(
                Array(words.dropFirst()),
                values: values
           ),
           remainder < 100 {
            return String(first * 100 + remainder)
        }
        return englishIntegerValue(words, values: values).map(String.init)
    }

    static func koreanOrdinalValue(_ raw: String) -> String? {
        [
            "첫째": "1", "둘째": "2", "셋째": "3", "넷째": "4",
            "다섯째": "5", "여섯째": "6", "일곱째": "7",
            "여덟째": "8", "아홉째": "9", "열째": "10",
        ][raw]
    }

    static let englishDigitWords = [
        "zero": "0", "one": "1", "two": "2", "three": "3",
        "four": "4", "five": "5", "six": "6", "seven": "7",
        "eight": "8", "nine": "9",
    ]

    static let englishCardinalValues = [
        "zero": 0, "one": 1, "first": 1, "two": 2, "second": 2,
        "three": 3, "third": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    static func englishIntegerValue(
        _ words: [Substring],
        values: [String: Int]
    ) -> Int? {
        var total = 0
        var current = 0
        for wordSlice in words {
            let word = String(wordSlice)
            if word == "and" { continue }
            if let value = values[word] {
                current += value
            } else if word == "hundred" {
                current = max(1, current) * 100
            } else if word == "thousand" || word == "million" {
                let scale = word == "thousand" ? 1_000 : 1_000_000
                total += max(1, current) * scale
                current = 0
            } else {
                return nil
            }
        }
        return total + current
    }
}
