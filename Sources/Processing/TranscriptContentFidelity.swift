import Foundation

extension TranscriptFidelityGuard {
    static func contentFidelityViolation(
        source: String,
        candidate: String
    ) -> String? {
        let sourceUnits = fidelityContentUnits(
            removingSelfCorrectionContent(
                from: removingDisfluencyMarkers(from: source)
            ),
            pairedWith: candidate
        )
        let candidateUnits = fidelityContentUnits(
            removingDisfluencyMarkers(from: candidate),
            pairedWith: source
        )
        guard !candidateUnits.isEmpty else { return "empty_output" }
        guard !sourceUnits.isEmpty else { return nil }

        if candidateUnits.count > Int(Double(sourceUnits.count) * 1.35) + 3 {
            return "excessive_expansion"
        }
        if sourceUnits.count >= 6,
           candidateUnits.count * 100 < sourceUnits.count * 55 {
            return "excessive_deletion"
        }

        let sourceSample = comparisonSample(sourceUnits)
        let candidateSample = comparisonSample(candidateUnits)
        let denominator = sourceSample.count
        guard denominator > 0 else { return nil }
        let overlap = longestCommonSubsequenceLength(
            sourceSample,
            candidateSample
        )
        let requiredOverlap = denominator <= 8 ? 80 : 55
        return overlap * 100 < denominator * requiredOverlap
            ? "content_drift" : nil
    }

    static func contentUnits(_ text: String) -> [String] {
        let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
        var units: [String] = []
        var asciiWord = ""
        func flushASCIIWord() {
            guard !asciiWord.isEmpty else { return }
            units.append(asciiWord)
            asciiWord.removeAll(keepingCapacity: true)
        }
        for character in normalized {
            if character.isASCIIWord {
                asciiWord.append(character)
            } else {
                flushASCIIWord()
                if character.isLetter || character.isNumber {
                    units.append(String(character))
                }
            }
        }
        flushASCIIWord()
        return units
    }

    static func comparisonSample(_ units: [String]) -> [String] {
        guard units.count > 1_024 else { return units }
        let step = Double(units.count - 1) / 1_023
        return (0..<1_024).map { offset in
            units[Int((Double(offset) * step).rounded())]
        }
    }

    static func longestCommonSubsequenceLength(
        _ lhs: [String],
        _ rhs: [String]
    ) -> Int {
        var lengths = Array(repeating: 0, count: rhs.count + 1)
        for left in lhs {
            var diagonal = 0
            for index in rhs.indices {
                let previous = lengths[index + 1]
                if left == rhs[index] {
                    lengths[index + 1] = diagonal + 1
                } else {
                    lengths[index + 1] = max(
                        lengths[index + 1],
                        lengths[index]
                    )
                }
                diagonal = previous
            }
        }
        return lengths[rhs.count]
    }

    static func fidelityContentUnits(
        _ text: String,
        pairedWith otherText: String
    ) -> [String] {
        let numbers = numericSemanticValues(in: text)
        let units = contentUnits(
            numbers.isEmpty ? text : removingRecognizedNumberEvidence(from: text)
        )
        guard !numbers.isEmpty,
              numbers == numericSemanticValues(in: otherText) else {
            return units
        }
        let numericWords: Set<String> = [
            "zero", "one", "two", "three", "four", "five", "six",
            "seven", "eight", "nine", "ten", "eleven", "twelve",
            "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
            "eighteen", "nineteen", "twenty", "thirty", "forty",
            "fifty", "sixty", "seventy", "eighty", "ninety",
            "hundred", "thousand", "million", "first", "second",
            "third", "half", "quarter",
            "from", "to",
            "second", "seconds", "minute", "minutes", "hour", "hours",
            "day", "days", "month", "months", "year", "years",
            "meter", "meters", "metre", "metres", "degree", "degrees",
            "dollar", "dollars", "page", "pages", "time", "times",
            "kg", "kilogram", "kilograms", "lb", "lbs", "pound", "pounds",
            "km", "cm", "mm", "ml", "mb", "gb", "tb",
            "celsius", "fahrenheit",
        ]
        let numericCharacters = Set(
            "0123456789零〇一二两兩三四五六七八九十百千万萬亿億兆"
                + "第百分之点點到至年月日时時分秒步页頁次元块塊米度"
        )
        let filtered = units.filter { unit in
            if numericWords.contains(unit) { return false }
            if unit.allSatisfy(\.isNumber) { return false }
            return !(unit.count == 1 && unit.first.map(numericCharacters.contains) == true)
        }
        return filtered.isEmpty ? ["#numeric"] : filtered
    }

    static func removingDisfluencyMarkers(from text: String) -> String {
        let patterns = [
            #"(?i)\b(?:um+|uh+|you know)\b[\s,;:，。；：]*"#,
            #"(?:嗯+|呃+|额+|えっと|あのー?|음+|저기)[\s,;:，。；：]*"#,
        ]
        return patterns.reduce(text) { result, pattern in
            let range = NSRange(result.startIndex..., in: result)
            return (try! NSRegularExpression(pattern: pattern))
                .stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
    }

    static func removingSelfCorrectionContent(from text: String) -> String {
        let patterns = [
            #"(?:唔係|不是)(?:星期|禮拜|礼拜|周)?[零〇一二两兩三四五六七八九十]+[\s，,]*(?:係|是)"#,
            #"(?:星期|禮拜|礼拜|周)?[零〇一二两兩三四五六七八九十]+[\s，,]*(?:不对|講錯咗|说错了)[\s，,]*"#,
            #"(?i)\b\w+[\s,]+(?:sorry|i mean|correction)[\s,]+"#,
            #"[^、。！？,\s]+(?:じゃなくて|ではなく)[、,\s]*"#,
            #"[^,.!?\s]+[\s,]*(?:아니고|정정)[\s,]*"#,
        ]
        return patterns.reduce(text) { result, pattern in
            let range = NSRange(result.startIndex..., in: result)
            return (try! NSRegularExpression(pattern: pattern))
                .stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: ""
                )
        }
    }
}

extension Character {
    var isASCIIWord: Bool {
        guard unicodeScalars.count == 1,
              let value = unicodeScalars.first?.value else {
            return false
        }
        return (48...57).contains(value)
            || (65...90).contains(value)
            || value == 95
            || (97...122).contains(value)
    }
}
