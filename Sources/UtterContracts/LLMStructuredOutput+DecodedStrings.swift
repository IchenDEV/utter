import Foundation

extension LLMStructuredOutput {
    struct IndexedJSONData {
        let index: String.Index
        let sequence: Int
        let data: Data
    }

    static func indexedJSONObjectDataCandidates(in text: String) -> [IndexedJSONData] {
        var candidates: [IndexedJSONData] = []
        var sequence = 0

        func append(_ data: Data, at index: String.Index) {
            candidates.append(IndexedJSONData(index: index, sequence: sequence, data: data))
            sequence += 1
        }

        for range in balancedJSONObjectRanges(in: text) {
            guard let data = String(text[range]).data(using: .utf8) else { continue }
            append(data, at: range.lowerBound)
        }
        for literal in decodedJSONStringLiterals(in: text) {
            for data in validJSONObjectDataCandidates(in: literal.value) {
                append(data, at: literal.index)
            }
        }
        return candidates.sorted(by: candidateSort)
    }

    static func indexedJSONValueDataCandidates(in text: String) -> [IndexedJSONData] {
        var candidates: [IndexedJSONData] = []
        var sequence = 0

        func append(_ data: Data, at index: String.Index) {
            candidates.append(IndexedJSONData(index: index, sequence: sequence, data: data))
            sequence += 1
        }

        for range in balancedJSONValueRanges(in: text) {
            guard let data = String(text[range]).data(using: .utf8) else { continue }
            append(data, at: range.lowerBound)
        }
        for literal in decodedJSONStringLiterals(in: text) {
            for data in validJSONValueDataCandidates(in: literal.value) {
                append(data, at: literal.index)
            }
        }
        return candidates.sorted(by: candidateSort)
    }

    package static func validJSONObjectDataCandidates(in text: String) -> [Data] {
        var candidates: [Data] = []
        for range in balancedJSONObjectRanges(in: text) {
            guard let data = validJSONObjectData(from: String(text[range])) else { continue }
            candidates.append(data)
        }
        for literal in decodedJSONStringLiterals(in: text) {
            candidates.append(contentsOf: validJSONObjectDataCandidates(in: literal.value))
        }
        return candidates
    }

    package static func validJSONValueDataCandidates(in text: String) -> [Data] {
        var candidates: [Data] = []
        for range in balancedJSONValueRanges(in: text) {
            guard let data = validJSONValueData(from: String(text[range])) else { continue }
            candidates.append(data)
        }
        for literal in decodedJSONStringLiterals(in: text) {
            candidates.append(contentsOf: validJSONValueDataCandidates(in: literal.value))
        }
        return candidates
    }
}

private extension LLMStructuredOutput {
    static func candidateSort(_ lhs: IndexedJSONData, _ rhs: IndexedJSONData) -> Bool {
        if lhs.index == rhs.index {
            return lhs.sequence < rhs.sequence
        }
        return lhs.index < rhs.index
    }

    static func validJSONObjectData(from text: String) -> Data? {
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            return nil
        }
        return data
    }

    static func validJSONValueData(from text: String) -> Data? {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              value is [String: Any] || value is [Any] else {
            return nil
        }
        return data
    }

    static func decodedJSONStringLiterals(in text: String) -> [(index: String.Index, value: String)] {
        var values: [(String.Index, String)] = []
        var start: String.Index?
        var index = text.startIndex
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            if let literalStart = start {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    let literal = String(text[literalStart...index])
                    if let data = literal.data(using: .utf8),
                       let value = try? JSONDecoder().decode(String.self, from: data),
                       value.contains("{") || value.contains("[") {
                        values.append((literalStart, value))
                    }
                    start = nil
                }
            } else if character == "\"" {
                start = index
                isEscaped = false
            }
            index = text.index(after: index)
        }
        return values
    }
}
