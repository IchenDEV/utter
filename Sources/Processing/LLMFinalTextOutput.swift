import Foundation

enum LLMFinalTextOutput {
    static func text(from rawText: String) -> String? {
        wholeJSONText(from: rawText)
    }

    /// Restricted entry point for the remote-API boundary: only extracts when
    /// the entire payload (optionally fenced) is one structured final-text
    /// value. Text that merely embeds JSON is left untouched.
    static func wholeJSONText(from rawText: String) -> String? {
        finalText(
            from: wholeJSONValueData(from: stripWrappingCodeFence(from: rawText)),
            allowsAmbiguousKeys: false
        )
    }
}

private extension LLMFinalTextOutput {
    static let explicitTextKeys = [
        "final_text", "finalText", "formatted_text", "formattedText",
        "cleaned_text", "cleanedText", "rewritten_text", "rewrittenText",
        "output_text", "outputText", "result_text", "resultText",
    ]
    static let typedFinalTextValues = [
        "output_text", "final_text", "formatted_text", "cleaned_text", "rewritten_text",
    ]
    static let typedFinalTextPayloadKeys = [
        "text", "content", "value", "output", "data",
    ]
    static let valueEnvelopeKeys = [
        "value",
    ]
    static let wrapperKeys = [
        "data", "payload", "result", "output", "response",
        "parsed", "output_parsed",
        "json",
        "choices", "message", "delta", "content",
        "tool_call", "tool_calls", "function_call", "function", "tool_use",
        "arguments", "input", "parameters", "params", "args",
    ]
    static let responseWrapperKeys = [
        "choices", "output", "message", "content",
    ]
    static let ambiguousTextKeys = [
        "text", "output", "result", "content", "body", "message", "response",
    ]
    static let metadataKeys = [
        "explanation", "reason", "rationale", "justification", "note", "notes",
        "confidence", "score", "probability", "certainty",
        "language", "locale", "type", "kind",
    ]

    static func finalText(from data: Data?, allowsAmbiguousKeys: Bool) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return finalText(in: object, allowsAmbiguousKeys: allowsAmbiguousKeys)
    }

    static func wholeJSONValueData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              value is [String: Any] || value is [Any] else {
            return nil
        }
        return data
    }

    static func finalText(in value: Any, allowsAmbiguousKeys: Bool) -> String? {
        if let text = explicitFinalText(in: value) {
            return text
        }

        if let array = value as? [Any] {
            let parts = array.compactMap { finalText(in: $0, allowsAmbiguousKeys: false) }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: "\n")
        }

        guard let object = value as? [String: Any] else { return nil }

        if let text = responseWrapperText(in: object) {
            return text
        }
        guard allowsAmbiguousKeys || hasMetadata(in: object) else { return nil }
        for key in ambiguousTextKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let text = finalTextValue(from: rawValue, allowsAmbiguousKeys: true) else {
                continue
            }
            return text
        }
        return nil
    }

    static func responseWrapperText(in object: [String: Any]) -> String? {
        for key in responseWrapperKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  isStructuredValue(rawValue),
                  let text = finalTextValue(from: rawValue, allowsAmbiguousKeys: false) else {
                continue
            }
            return text
        }
        return nil
    }

    static func explicitFinalText(in value: Any) -> String? {
        if let text = value as? String {
            return nestedStructuredFinalText(in: text)
        }

        if let array = value as? [Any] {
            let parts = array.compactMap { explicitFinalText(in: $0) }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: "\n")
        }

        guard let object = value as? [String: Any] else { return nil }
        for key in explicitTextKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let text = finalTextValue(from: rawValue, allowsAmbiguousKeys: true) else {
                continue
            }
            return text
        }
        if let text = typedFinalText(in: object) {
            return text
        }
        for key in wrapperKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let text = explicitFinalText(in: rawValue) else {
                continue
            }
            return text
        }
        return nil
    }

    static func typedFinalText(in object: [String: Any]) -> String? {
        guard let kind = object.value(forCaseInsensitiveKey: "type") as? String,
              typedFinalTextValues.contains(where: { normalizedKind(kind) == normalizedKind($0) }) else {
            return nil
        }
        for key in typedFinalTextPayloadKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let text = finalTextValue(from: rawValue, allowsAmbiguousKeys: true) else {
                continue
            }
            return text
        }
        return nil
    }

    static func isStructuredValue(_ value: Any) -> Bool {
        value is [String: Any] || value is [Any]
    }

    static func finalTextValue(from value: Any, allowsAmbiguousKeys: Bool) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return nestedStructuredFinalText(in: trimmed) ?? trimmed
        }
        if let object = value as? [String: Any] {
            if allowsAmbiguousKeys,
               let text = valueEnvelopeText(in: object) {
                return text
            }
            return finalText(in: object, allowsAmbiguousKeys: allowsAmbiguousKeys)
        }
        if let array = value as? [Any] {
            let parts = array.compactMap {
                finalTextValue(from: $0, allowsAmbiguousKeys: allowsAmbiguousKeys)
            }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: "\n")
        }
        return nil
    }

    static func valueEnvelopeText(in object: [String: Any]) -> String? {
        for key in valueEnvelopeKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let text = finalTextValue(from: rawValue, allowsAmbiguousKeys: false) else {
                continue
            }
            return text
        }
        return nil
    }

    static func nestedStructuredFinalText(in text: String) -> String? {
        finalText(
            from: wholeJSONValueData(from: stripWrappingCodeFence(from: text)),
            allowsAmbiguousKeys: false
        )
    }

    static func hasMetadata(in object: [String: Any]) -> Bool {
        metadataKeys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
    }

    static func normalizedKind(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func stripWrappingCodeFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2,
              isOpeningCodeFence(lines[0]),
              lines[lines.count - 1].trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
            return trimmed
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    static func isOpeningCodeFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "```" || trimmed.range(of: #"^```[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}
