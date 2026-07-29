import Foundation

enum RemoteLLMResponseTruncation {
    static func validateOpenAI(
        data: Data,
        json: [String: Any]?
    ) throws {
        if let json {
            if contains(
                key: "finish_reason",
                value: "length",
                in: json
            ) || (
                contains(key: "status", value: "incomplete", in: json)
                    && contains(
                        key: "reason",
                        value: "max_output_tokens",
                        in: json
                    )
            ) {
                throw RemoteLLMError.requestFailed(
                    "provider returned truncated output"
                )
            }
            return
        }
        try validateEventStream(
            data,
            patternGroups: [
                [#""finish_reason"\s*:\s*"length""#],
                [
                    #""status"\s*:\s*"incomplete""#,
                    #""reason"\s*:\s*"max_output_tokens""#,
                ],
            ]
        )
    }

    static func validateAnthropic(
        data: Data,
        json: [String: Any]?
    ) throws {
        if let json {
            if contains(key: "stop_reason", value: "max_tokens", in: json) {
                throw RemoteLLMError.requestFailed(
                    "provider returned truncated output"
                )
            }
            return
        }
        try validateEventStream(
            data,
            patternGroups: [[#""stop_reason"\s*:\s*"max_tokens""#]]
        )
    }

    private static func contains(
        key expectedKey: String,
        value expectedValue: String,
        in value: Any
    ) -> Bool {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                if key.caseInsensitiveCompare(expectedKey) == .orderedSame,
                   let string = child as? String,
                   string.caseInsensitiveCompare(expectedValue) == .orderedSame {
                    return true
                }
                if contains(
                    key: expectedKey,
                    value: expectedValue,
                    in: child
                ) {
                    return true
                }
            }
        } else if let array = value as? [Any] {
            return array.contains {
                contains(
                    key: expectedKey,
                    value: expectedValue,
                    in: $0
                )
            }
        }
        return false
    }

    private static func validateEventStream(
        _ data: Data,
        patternGroups: [[String]]
    ) throws {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let hasTruncation = patternGroups.contains { patterns in
            patterns.allSatisfy { pattern in
                text.range(
                    of: pattern,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
            }
        }
        if hasTruncation {
            throw RemoteLLMError.requestFailed(
                "provider returned truncated output"
            )
        }
    }
}
