import Foundation

enum RemoteLLMStreamContentDeltaText {
    static func text(from value: Any) -> String? {
        if let text = value as? String {
            return text.isEmpty ? nil : text
        }
        if let blocks = value as? [Any] {
            let text = blocks.compactMap(Self.text).joined()
            return text.isEmpty ? nil : text
        }
        guard let object = value as? [String: Any] else { return nil }
        return contentBlockText(object)
            ?? RemoteLLMResponseText.openAIText(in: ["choices": [["delta": ["content": value]]]])
    }
}

private extension RemoteLLMStreamContentDeltaText {
    static func contentBlockText(_ object: [String: Any]) -> String? {
        if let type = object.value(forCaseInsensitiveKey: "type") as? String {
            if RemoteLLMPayload.matchesBlockType(type, in: textBlockTypes) {
                return firstText(in: object, keys: ["text", "content", "value"])
            }
            if RemoteLLMPayload.matchesBlockType(type, in: deltaBlockTypes) {
                return firstText(in: object, keys: ["delta", "text", "content", "value"])
            }
            if RemoteLLMPayload.matchesBlockType(type, in: wrapperBlockTypes) {
                return firstText(in: object, keys: ["content", "output", "value", "text"])
            }
            return nil
        }
        return firstText(in: object, keys: ["text", "content", "value"])
    }

    static func firstText(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = text(from: value) else {
                continue
            }
            return text
        }
        return nil
    }

    static let textBlockTypes = [
        "text", "output_text", "final_text", "formatted_text", "cleaned_text",
        "rewritten_text", "result_text",
    ]
    static let deltaBlockTypes = [
        "text_delta", "output_text_delta", "final_text_delta", "formatted_text_delta",
        "cleaned_text_delta", "rewritten_text_delta", "result_text_delta",
    ]
    static let wrapperBlockTypes = ["message"]

}
