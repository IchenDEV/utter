import Foundation

struct LLMTextValue: Decodable, Equatable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            text = ""
        } else if let value = try? container.decode(String.self) {
            text = value
        } else if let value = try? container.decode(Int.self) {
            text = String(value)
        } else if let value = try? container.decode(Double.self) {
            text = String(value)
        } else if let value = try? container.decode(Bool.self) {
            text = value ? "true" : "false"
        } else if let value = try? container.decode([LLMTextValue].self) {
            text = Self.describe(array: value)
        } else if let value = try? container.decode([String: LLMTextValue].self) {
            text = Self.describe(object: value)
        } else {
            text = ""
        }
    }
}

private extension LLMTextValue {
    static let singleValueObjectKeys = [
        "text", "value",
        "intent", "instruction", "editInstruction", "edit_instruction",
        "rewriteInstruction", "rewrite_instruction",
        "task", "goal", "objective", "directive",
        "preset", "style", "format", "mode", "category", "targetStyle", "target_style",
        "label", "name", "replacement", "kind", "type",
    ]
    static let structuralTypeValues = [
        "custom", "preset", "intent", "instruction", "task",
        "style", "format", "category", "metadata", "object",
    ]
    static let metadataObjectKeys = [
        "confidence", "score", "probability", "certainty", "reason", "rationale",
        "justification", "description", "explanation", "note", "notes", "kind", "type",
        "percent", "percentage", "pct",
        "confidencePercent", "confidence_percent", "confidencePct", "confidence_pct",
        "confidencePercentage", "confidence_percentage",
    ]

    static func describe(array: [LLMTextValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMTextValue]) -> String {
        if object.count == 1,
           let key = singleValueObjectKeys.first(where: { object.value(forCaseInsensitiveKey: $0) != nil }),
           let value = object.value(forCaseInsensitiveKey: key)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !isStructuralTypeValue(value, for: key),
           !value.isEmpty {
            return value
        }
        if let semanticValue = singleSemanticValue(in: object) {
            return semanticValue
        }

        return object.keys.sorted().compactMap { key in
            let value = object[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        .joined(separator: "; ")
    }

    static func singleSemanticValue(in object: [String: LLMTextValue]) -> String? {
        for key in singleValueObjectKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }
            guard !isStructuralTypeValue(value, for: key) else { continue }

            let hasOnlyMetadataBesidesValue = object.allSatisfy { objectKey, objectValue in
                let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return candidate.isEmpty
                    || objectKey.localizedCaseInsensitiveCompare(key) == .orderedSame
                    || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
            }
            if hasOnlyMetadataBesidesValue {
                return value
            }
        }
        return nil
    }

    static func isStructuralTypeValue(_ value: String, for key: String) -> Bool {
        guard key.localizedCaseInsensitiveCompare("type") == .orderedSame
            || key.localizedCaseInsensitiveCompare("kind") == .orderedSame else {
            return false
        }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return structuralTypeValues.contains(normalized)
    }
}

struct LLMReplacementValue: Decodable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            text = ""
        } else if let value = try? container.decode(String.self) {
            text = value
        } else if let value = try? container.decode(Int.self) {
            text = String(value)
        } else if let value = try? container.decode(Double.self) {
            text = String(value)
        } else if let value = try? container.decode(Bool.self) {
            text = value ? "true" : "false"
        } else if let value = try? container.decode([LLMReplacementValue].self) {
            text = Self.describe(array: value)
        } else if let value = try? container.decode([String: LLMReplacementValue].self) {
            text = Self.describe(object: value)
        } else {
            text = ""
        }
    }
}

private extension LLMReplacementValue {
    static let preferredObjectKeys = [
        "replacement", "replacementText", "replacement_text", "text", "value",
        "content", "body", "message", "response", "output",
        "new", "newText", "new_text", "to", "toText", "to_text", "after", "target",
        "final", "finalText", "final_text", "outputText", "output_text",
        "resultText", "result_text", "updated", "updatedText", "updated_text",
        "corrected", "correctedText", "corrected_text", "revised", "revisedText",
        "revised_text", "current",
    ]
    static let metadataObjectKeys = [
        "old", "oldText", "old_text", "from", "fromText", "from_text", "before",
        "source", "original", "previous", "language", "locale", "format",
        "confidence", "score", "probability", "certainty", "reason", "rationale",
        "justification", "description", "explanation", "note", "notes", "kind", "type",
        "percent", "percentage", "pct",
        "confidencePercent", "confidence_percent", "confidencePct", "confidence_pct",
        "confidencePercentage", "confidence_percentage",
    ]

    static func describe(array: [LLMReplacementValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMReplacementValue]) -> String {
        if let value = semanticReplacementValue(in: object) {
            return value
        }

        return object.keys.sorted().compactMap { key in
            let value = object[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        .joined(separator: "; ")
    }

    static func semanticReplacementValue(in object: [String: LLMReplacementValue]) -> String? {
        for key in preferredObjectKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }

            let hasOnlyReplacementOrMetadata = object.allSatisfy { objectKey, objectValue in
                let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return candidate.isEmpty
                    || preferredObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                    || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
            }
            if hasOnlyReplacementOrMetadata {
                return value
            }
        }
        return nil
    }
}

struct LLMNumericConfidence: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = Self.normalized(number)
        } else if let raw = try? container.decode(String.self) {
            value = Self.number(from: raw)
        } else if let object = try? container.decode([String: LLMNumericConfidence].self),
                  let nested = Self.nestedConfidence(in: object) {
            value = nested
        } else {
            value = -1
        }
    }
}

struct LLMResolutionCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private extension LLMNumericConfidence {
    static let confidenceKeys = [
        "value", "score", "confidence", "probability",
        "certainty", "confidenceScore", "confidence_score",
        "percent", "percentage", "pct",
        "confidencePercent", "confidence_percent", "confidencePct", "confidence_pct",
        "confidencePercentage", "confidence_percentage",
    ]

    static func nestedConfidence(in object: [String: LLMNumericConfidence]) -> Double? {
        for key in confidenceKeys {
            if let confidence = object.value(forCaseInsensitiveKey: key)?.value {
                return confidence
            }
        }
        return nil
    }

    static func number(from raw: String) -> Double {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("%"),
           let percent = Double(text.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)),
           (0...100).contains(percent) {
            return percent / 100
        }
        guard let number = Double(text) else { return -1 }
        return normalized(number)
    }

    static func normalized(_ number: Double) -> Double {
        if (0...1).contains(number) {
            return number
        }
        if number > 1, number <= 100 {
            return number / 100
        }
        return -1
    }
}

extension Dictionary where Key == String {
    func value(forCaseInsensitiveKey key: String) -> Value? {
        if let value = self[key] {
            return value
        }
        return first { $0.key.localizedCaseInsensitiveCompare(key) == .orderedSame }?.value
    }
}

extension KeyedDecodingContainer where Key == LLMResolutionCodingKey {
    func caseInsensitiveKey(_ name: String) -> Key? {
        allKeys.first { $0.stringValue.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func decodeIfPresentCaseInsensitive<T: Decodable>(_ type: T.Type, forKey name: String) throws -> T? {
        guard let key = caseInsensitiveKey(name) else { return nil }
        return try decodeIfPresent(type, forKey: key)
    }
}
