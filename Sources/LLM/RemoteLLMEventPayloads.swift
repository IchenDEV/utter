import Foundation

enum RemoteLLMEventPayloads {
    static func values(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let ssePayloads = sseValues(in: normalized)
        if !ssePayloads.isEmpty { return ssePayloads }

        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("{") || $0.hasPrefix("[") }
    }
}

enum RemoteLLMPayload {
    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func int(from value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func jsonString(from value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return nonEmpty(text)
    }

    static func matchesBlockType(_ type: String, in candidates: [String]) -> Bool {
        let normalized = normalizedBlockType(type)
        return candidates.contains { normalizedBlockType($0) == normalized }
    }

    private static func normalizedBlockType(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}

private extension RemoteLLMEventPayloads {
    static func sseValues(in text: String) -> [String] {
        var payloads: [String] = []
        var dataLines: [String] = []
        var eventName: String?

        func flush() {
            guard !dataLines.isEmpty else { return }
            let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            payloads.append(payloadWithEventType(payload, eventName: eventName))
            dataLines.removeAll()
            eventName = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                flush()
                continue
            }
            let rawLine = String(line)
            if rawLine.localizedCaseInsensitiveComparePrefix("event:") {
                eventName = String(rawLine.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard rawLine.localizedCaseInsensitiveComparePrefix("data:") else { continue }
            dataLines.append(String(rawLine.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        flush()
        return payloads.filter { !$0.isEmpty }
    }

    static func payloadWithEventType(_ payload: String, eventName: String?) -> String {
        guard let eventName,
              !eventName.isEmpty,
              let data = payload.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.value(forCaseInsensitiveKey: "type") == nil else {
            return payload
        }
        object["type"] = eventName
        guard JSONSerialization.isValidJSONObject(object),
              let typedData = try? JSONSerialization.data(withJSONObject: object),
              let typedPayload = String(data: typedData, encoding: .utf8) else {
            return payload
        }
        return typedPayload
    }
}

private extension String {
    func localizedCaseInsensitiveComparePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }
}
