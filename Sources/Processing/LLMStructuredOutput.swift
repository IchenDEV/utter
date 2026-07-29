import Foundation

enum LLMStructuredOutput {
    static func firstJSONObjectData(from text: String) -> Data? {
        guard let range = firstBalancedJSONObjectRange(in: text) else { return nil }
        return String(text[range]).data(using: .utf8)
    }

    static func jsonObjectDataCandidates(from text: String) -> [Data] {
        var candidates: [Data] = []
        var seen: Set<String> = []

        func appendCandidate(_ data: Data) {
            guard candidates.count < maxJSONObjectCandidates,
                  let key = String(data: data, encoding: .utf8),
                  !seen.contains(key) else {
                return
            }
            seen.insert(key)
            candidates.append(data)
        }

        for candidate in indexedJSONObjectDataCandidates(in: text) {
            appendCandidate(candidate.data)
        }

        var index = 0
        while index < candidates.count, candidates.count < maxJSONObjectCandidates {
            for data in embeddedJSONObjectDataCandidates(in: candidates[index]) {
                appendCandidate(data)
            }
            index += 1
        }

        return candidates
    }

    static func jsonValueDataCandidates(from text: String) -> [Data] {
        var candidates: [Data] = []
        var seen: Set<String> = []

        func appendCandidate(_ data: Data) {
            guard candidates.count < maxJSONCandidates,
                  let key = String(data: data, encoding: .utf8),
                  !seen.contains(key) else {
                return
            }
            seen.insert(key)
            candidates.append(data)
        }

        for candidate in indexedJSONValueDataCandidates(in: text) {
            appendCandidate(candidate.data)
        }

        var index = 0
        while index < candidates.count, candidates.count < maxJSONCandidates {
            for data in embeddedJSONValueDataCandidates(in: candidates[index]) {
                appendCandidate(data)
            }
            index += 1
        }

        return candidates
    }

    static func firstBalancedJSONObjectRange(in text: String) -> ClosedRange<String.Index>? {
        balancedJSONObjectRanges(in: text).first
    }

    static func balancedJSONObjectRanges(in text: String) -> [ClosedRange<String.Index>] {
        var ranges: [ClosedRange<String.Index>] = []
        var starts: [String.Index] = []
        var index = text.startIndex
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                starts.append(index)
            } else if character == "}" {
                guard let start = starts.popLast() else {
                    index = text.index(after: index)
                    continue
                }
                ranges.append(start...index)
            }
            index = text.index(after: index)
        }
        return ranges.sorted { lhs, rhs in
            if lhs.lowerBound == rhs.lowerBound {
                return lhs.upperBound > rhs.upperBound
            }
            return lhs.lowerBound < rhs.lowerBound
        }
    }

    static func balancedJSONValueRanges(in text: String) -> [ClosedRange<String.Index>] {
        var ranges: [ClosedRange<String.Index>] = []
        var stack: [Character] = []
        var rootStart: String.Index?
        var index = text.startIndex
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" || character == "[" {
                if stack.isEmpty {
                    rootStart = index
                }
                stack.append(character == "{" ? "}" : "]")
            } else if character == "}" || character == "]" {
                guard stack.last == character else {
                    stack.removeAll()
                    rootStart = nil
                    index = text.index(after: index)
                    continue
                }
                stack.removeLast()
                if stack.isEmpty, let start = rootStart {
                    ranges.append(start...index)
                    rootStart = nil
                }
            }
            index = text.index(after: index)
        }
        return ranges
    }
}

private extension LLMStructuredOutput {
    static let maxJSONCandidates = 32
    static let maxJSONObjectCandidates = maxJSONCandidates

    static func embeddedJSONObjectDataCandidates(in data: Data) -> [Data] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return embeddedJSONObjectDataCandidates(in: object)
    }

    static func embeddedJSONObjectDataCandidates(in object: Any) -> [Data] {
        var candidates: [Data] = []

        func collect(_ value: Any) {
            if let string = value as? String {
                candidates.append(contentsOf: validJSONObjectDataCandidates(in: string))
            } else if let dictionary = value as? [String: Any] {
                for value in dictionary.values {
                    collect(value)
                }
            } else if let array = value as? [Any] {
                for value in array {
                    collect(value)
                }
            }
        }

        collect(object)
        return candidates
    }

    static func embeddedJSONValueDataCandidates(in data: Data) -> [Data] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return embeddedJSONValueDataCandidates(in: object)
    }

    static func embeddedJSONValueDataCandidates(in object: Any) -> [Data] {
        var candidates: [Data] = []

        func collect(_ value: Any) {
            if let string = value as? String {
                candidates.append(contentsOf: validJSONValueDataCandidates(in: string))
            } else if let dictionary = value as? [String: Any] {
                for value in dictionary.values {
                    collect(value)
                }
            } else if let array = value as? [Any] {
                for value in array {
                    collect(value)
                }
            }
        }

        collect(object)
        return candidates
    }
}

enum LLMResolutionFieldAlias {
    static let action = [
        "action", "actionType", "action_type",
        "command", "commandType", "command_type",
        "operation", "operationType", "operation_type",
        "type", "name",
    ]
    static let intent = [
        "intent", "instruction", "editInstruction", "edit_instruction",
        "rewriteInstruction", "rewrite_instruction",
        "task", "goal", "objective", "directive",
        "preset", "style",
        "format", "category", "targetStyle", "target_style",
    ]
    static let target = [
        "target", "scope", "object", "subject",
        "targetText", "target_text",
        "editTarget", "edit_target",
    ]
    static let replacement = [
        "replacement", "replacementText", "replacement_text",
        "text", "value", "content", "body", "message", "response",
        "new", "newText", "new_text", "newValue", "new_value",
        "to", "toText", "to_text", "after", "current",
        "output", "outputText", "output_text", "resultText", "result_text",
        "final", "finalText", "final_text",
        "updated", "updatedText", "updated_text",
        "corrected", "correctedText", "corrected_text",
        "revised", "revisedText", "revised_text",
    ]
    static let confidence = [
        "confidence", "score", "probability", "certainty",
        "confidenceScore", "confidence_score",
        "percent", "percentage", "pct",
        "confidencePercent", "confidence_percent", "confidencePct", "confidence_pct",
        "confidencePercentage", "confidence_percentage",
    ]
}

extension KeyedDecodingContainer where Key == LLMResolutionCodingKey {
    func hasCaseInsensitiveKey(anyOf names: [String]) -> Bool {
        names.contains { caseInsensitiveKey($0) != nil }
    }

    func decodeIfPresentCaseInsensitive<T: Decodable>(
        _ type: T.Type,
        forAnyKey names: [String]
    ) throws -> T? {
        guard let name = names.first(where: { caseInsensitiveKey($0) != nil }) else { return nil }
        return try decodeIfPresentCaseInsensitive(type, forKey: name)
    }
}
