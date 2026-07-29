import Foundation

enum RemoteLLMEventStreamText {
    static func openAI(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        if let text = RemoteLLMResponsesEventStreamText.text(from: text) {
            return text
        }

        let payloads = RemoteLLMEventPayloads.values(in: text)
        guard !payloads.isEmpty else { return nil }

        var contentParts: [String] = []
        var toolArguments: [Int: String] = [:]
        var functionArguments = ""

        for payload in payloads {
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if hasDelta(in: json) {
                collectDeltaPayloads(
                    from: json,
                    contentParts: &contentParts,
                    toolArguments: &toolArguments,
                    functionArguments: &functionArguments
                )
            } else if let text = RemoteLLMResponseText.openAIText(in: json) {
                return text
            }
        }

        if let text = toolArgumentsText(toolArguments) {
            return text
        }
        if let text = functionArgumentsText(functionArguments) {
            return text
        }
        return RemoteLLMPayload.nonEmpty(contentParts.joined())
    }

    static func anthropic(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let payloads = RemoteLLMEventPayloads.values(in: text)
        guard !payloads.isEmpty else { return nil }

        var textParts: [Int: String] = [:]
        var toolInputs: [Int: String] = [:]

        for payload in payloads {
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let text = RemoteLLMResponseText.anthropicText(in: json) {
                return text
            }
            collectAnthropicPayload(from: json, textParts: &textParts, toolInputs: &toolInputs)
        }

        if let text = anthropicToolText(toolInputs) {
            return text
        }
        return anthropicText(textParts)
    }
}

private extension RemoteLLMEventStreamText {
    static func hasDelta(in json: [String: Any]) -> Bool {
        guard let choices = json.value(forCaseInsensitiveKey: "choices") as? [Any] else { return false }
        return choices.contains { choice in
            (choice as? [String: Any])?.value(forCaseInsensitiveKey: "delta") != nil
        }
    }

    static func collectDeltaPayloads(
        from json: [String: Any],
        contentParts: inout [String],
        toolArguments: inout [Int: String],
        functionArguments: inout String
    ) {
        guard let choices = json.value(forCaseInsensitiveKey: "choices") as? [Any] else { return }
        for case let choice as [String: Any] in choices {
            guard let delta = choice.value(forCaseInsensitiveKey: "delta") as? [String: Any] else { continue }
            if let content = delta.value(forCaseInsensitiveKey: "content") as? String {
                contentParts.append(content)
            } else if let content = delta.value(forCaseInsensitiveKey: "content"),
                      let text = RemoteLLMStreamContentDeltaText.text(from: content) {
                contentParts.append(text)
            }
            for key in ["tool_calls", "toolCalls", "tool_call", "toolCall"] {
                appendToolArguments(from: delta.value(forCaseInsensitiveKey: key), to: &toolArguments)
            }
            for key in ["function_call", "functionCall"] {
                appendFunctionArguments(from: delta.value(forCaseInsensitiveKey: key), to: &functionArguments)
            }
        }
    }

    static func appendToolArguments(from value: Any?, to toolArguments: inout [Int: String]) {
        let calls: [Any]
        if let array = value as? [Any] {
            calls = array
        } else if let object = value as? [String: Any] {
            calls = [object]
        } else {
            return
        }
        for (fallbackIndex, value) in calls.enumerated() {
            guard let call = value as? [String: Any] else { continue }
            let index = RemoteLLMPayload.int(
                from: call.value(forCaseInsensitiveKey: "index")
            ) ?? fallbackIndex
            if let arguments = argumentsText(in: call) {
                toolArguments[index, default: ""] += arguments
            }
            if let function = call.value(forCaseInsensitiveKey: "function") as? [String: Any],
               let arguments = argumentsText(in: function) {
                toolArguments[index, default: ""] += arguments
            }
        }
    }

    static func appendFunctionArguments(from value: Any?, to functionArguments: inout String) {
        guard let function = value as? [String: Any],
              let arguments = argumentsText(in: function) else {
            return
        }
        functionArguments += arguments
    }

    static func collectAnthropicPayload(
        from json: [String: Any],
        textParts: inout [Int: String],
        toolInputs: inout [Int: String]
    ) {
        let index = anthropicIndex(in: json)
        if let block = dictionaryValue(in: json, keys: ["content_block", "contentBlock"]) {
            collectAnthropicStartBlock(block, index: index, textParts: &textParts, toolInputs: &toolInputs)
        }

        guard let delta = json.value(forCaseInsensitiveKey: "delta") as? [String: Any] else {
            return
        }
        if let text = delta.value(forCaseInsensitiveKey: "text") as? String {
            textParts[index, default: ""] += text
        }
        if let partialJSON = stringValue(in: delta, keys: ["partial_json", "partialJson"]) {
            toolInputs[index, default: ""] += partialJSON
        }
    }

    static func collectAnthropicStartBlock(
        _ block: [String: Any],
        index: Int,
        textParts: inout [Int: String],
        toolInputs: inout [Int: String]
    ) {
        if let text = block.value(forCaseInsensitiveKey: "text") as? String {
            textParts[index, default: ""] += text
        }
        if let input = firstValue(in: block, keys: ["input", "input_json", "inputJson"]),
           let text = RemoteLLMPayload.jsonString(from: input) {
            guard text != "{}" else { return }
            toolInputs[index, default: ""] += text
        }
    }

    static func anthropicIndex(in object: [String: Any]) -> Int {
        RemoteLLMPayload.int(from: firstValue(
            in: object,
            keys: ["index", "content_block_index", "contentBlockIndex", "content_index", "contentIndex"]
        )) ?? 0
    }

    static func firstValue(in object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = object.value(forCaseInsensitiveKey: key) {
                return value
            }
        }
        return nil
    }

    static func dictionaryValue(in object: [String: Any], keys: [String]) -> [String: Any]? {
        firstValue(in: object, keys: keys) as? [String: Any]
    }

    static func stringValue(in object: [String: Any], keys: [String]) -> String? {
        firstValue(in: object, keys: keys) as? String
    }

    static func argumentsText(in object: [String: Any]) -> String? {
        for key in ["arguments", "args", "parameters", "params", "input"] {
            guard let value = object.value(forCaseInsensitiveKey: key) else { continue }
            if let text = value as? String, !text.isEmpty {
                return text
            }
            if let text = RemoteLLMPayload.jsonString(from: value) {
                return text
            }
        }
        return nil
    }

    static func toolArgumentsText(_ toolArguments: [Int: String]) -> String? {
        for key in toolArguments.keys.sorted() {
            guard let text = payloadText(fromArguments: toolArguments[key] ?? "", toolKey: "tool_calls") else {
                continue
            }
            return text
        }
        return nil
    }

    static func functionArgumentsText(_ functionArguments: String) -> String? {
        payloadText(fromArguments: functionArguments, toolKey: "function_call")
    }

    static func anthropicToolText(_ toolInputs: [Int: String]) -> String? {
        for key in toolInputs.keys.sorted() {
            let input = normalizedAnthropicToolInput(toolInputs[key] ?? "")
            let payload: [String: Any] = ["content": [["type": "tool_use", "input": input]]]
            guard let text = RemoteLLMResponseText.anthropicText(in: payload) else { continue }
            return text
        }
        return nil
    }

    static func normalizedAnthropicToolInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{") else { return trimmed }
        return "{\(trimmed)}"
    }

    static func anthropicText(_ textParts: [Int: String]) -> String? {
        let parts = textParts.keys.sorted().compactMap {
            RemoteLLMPayload.nonEmpty(textParts[$0] ?? "")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    static func payloadText(fromArguments arguments: String, toolKey: String) -> String? {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let payload: [String: Any]
        if toolKey == "tool_calls" {
            payload = ["choices": [["message": ["tool_calls": [["function": ["arguments": trimmed]]]]]]]
        } else {
            payload = ["choices": [["message": ["function_call": ["arguments": trimmed]]]]]
        }
        return RemoteLLMResponseText.openAIText(in: payload)
    }

}
