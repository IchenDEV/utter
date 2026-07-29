import Foundation

enum RemoteLLMResponsesEventStreamText {
    static func text(from eventStream: String) -> String? {
        var textParts: [String] = []
        var functionArguments: [String: String] = [:]
        var sawResponsesEvent = false

        for payload in RemoteLLMEventPayloads.values(in: eventStream) {
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let type = (json.value(forCaseInsensitiveKey: "type") as? String) ?? ""
            let eventType = normalizedEventType(type)
            guard eventType.hasPrefix("response") else { continue }
            sawResponsesEvent = true

            switch eventType {
            case "responseoutputtextdelta":
                if let delta = json.value(forCaseInsensitiveKey: "delta") as? String {
                    textParts.append(delta)
                }
            case "responseoutputtextdone":
                if textParts.isEmpty,
                   let text = json.value(forCaseInsensitiveKey: "text") as? String {
                    textParts.append(text)
                }
            case "responsecontentpartdone":
                if let text = contentPartText(in: json) {
                    return text
                }
            case "responsefunctioncallargumentsdelta":
                if let delta = json.value(forCaseInsensitiveKey: "delta") as? String {
                    functionArguments[eventKey(in: json), default: ""] += delta
                }
            case "responsefunctioncallargumentsdone":
                if let arguments = argumentsText(from: json.value(forCaseInsensitiveKey: "arguments")) {
                    functionArguments[eventKey(in: json)] = arguments
                }
            case "responseoutputitemdone":
                if let item = json.value(forCaseInsensitiveKey: "item") as? [String: Any],
                   let text = RemoteLLMResponseText.openAIText(in: ["output": [item]]) {
                    return text
                }
            case "responsecompleted":
                if let response = json.value(forCaseInsensitiveKey: "response") as? [String: Any],
                   let text = RemoteLLMResponseText.openAIText(in: response) {
                    return text
                }
            default:
                if let text = RemoteLLMResponseText.openAIText(in: json) {
                    return text
                }
            }
        }

        guard sawResponsesEvent else { return nil }
        if let text = functionArgumentsText(functionArguments) {
            return text
        }
        return RemoteLLMPayload.nonEmpty(textParts.joined())
    }
}

private extension RemoteLLMResponsesEventStreamText {
    static func functionArgumentsText(_ functionArguments: [String: String]) -> String? {
        for key in functionArguments.keys.sorted() {
            let arguments = functionArguments[key] ?? ""
            let payload: [String: Any] = ["output": [["type": "function_call", "arguments": arguments]]]
            guard let text = RemoteLLMResponseText.openAIText(in: payload) else { continue }
            return text
        }
        return nil
    }

    static func argumentsText(from value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty {
            return text
        }
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func contentPartText(in json: [String: Any]) -> String? {
        for key in ["part", "content_part", "contentPart", "content"] {
            guard let value = json.value(forCaseInsensitiveKey: key),
                  let text = messageContentText(from: value) else {
                continue
            }
            return text
        }
        return nil
    }

    static func messageContentText(from value: Any) -> String? {
        let content: [Any]
        if let array = value as? [Any] {
            content = array
        } else {
            content = [value]
        }
        return RemoteLLMResponseText.openAIText(in: [
            "output": [["type": "message", "content": content]]
        ])
    }

    static func eventKey(in json: [String: Any]) -> String {
        if let itemID = json.value(forCaseInsensitiveKey: "item_id") as? String, !itemID.isEmpty {
            return itemID
        }
        if let outputIndex = RemoteLLMPayload.int(
            from: json.value(forCaseInsensitiveKey: "output_index")
        ) {
            return String(outputIndex)
        }
        return "0"
    }

    static func normalizedEventType(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

}
