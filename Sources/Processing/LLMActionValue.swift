import Foundation

struct LLMActionValue: Decodable {
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
        } else if let value = try? container.decode([LLMActionValue].self) {
            text = Self.describe(array: value)
        } else if let actionValues = try? container.decode([String: LLMActionValue].self) {
            let targetValues = (try? container.decode([String: LLMTargetValue].self)) ?? [:]
            text = Self.describe(actionObject: actionValues, targetObject: targetValues)
        } else {
            text = ""
        }
    }
}

private extension LLMActionValue {
    static let preferredObjectKeys = [
        "action", "actionType", "action_type",
        "command", "commandType", "command_type",
        "operation", "operationType", "operation_type",
        "value", "name", "type",
    ]
    static let booleanActionFlagKeys = [
        "replace", "rewrite", "delete", "undo",
        "replaceLast", "replace_last", "replaceSelection", "replace_selection",
        "rewriteLast", "rewrite_last", "rewriteSelection", "rewrite_selection",
        "deleteSelection", "delete_selection",
        "undoLastInsertion", "undo_last_insertion",
    ]
    static let targetObjectKeys = [
        "target", "scope", "object", "subject",
        "targetText", "target_text",
        "editTarget", "edit_target",
    ]
    static let targetContainerKeys = [
        "parameters", "params", "arguments", "args", "input",
    ]
    static let booleanTargetFlagKeys = [
        "selection", "selected", "selectedText", "selected_text",
        "currentSelection", "current_selection",
        "activeSelection", "active_selection",
        "last", "previous", "lastInsertion", "last_insertion",
        "previousInsertion", "previous_insertion",
        "lastOutput", "last_output",
    ]
    static let metadataObjectKeys = [
        "confidence", "score", "probability", "certainty", "reason", "rationale",
        "justification", "description", "explanation", "note", "notes", "kind",
        "percent", "percentage", "pct",
        "confidencePercent", "confidence_percent", "confidencePct", "confidence_pct",
        "confidencePercentage", "confidence_percentage",
    ]

    static func describe(array: [LLMActionValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMActionValue]) -> String {
        describe(actionObject: object, targetObject: [:])
    }

    static func describe(
        actionObject: [String: LLMActionValue],
        targetObject: [String: LLMTargetValue]
    ) -> String {
        let action = booleanFlagAction(in: actionObject, allowsTargetFields: true)
            ?? semanticActionValue(in: actionObject, allowsTargetFields: true)
        if let action {
            return targetedAction(action, target: targetValue(in: targetObject))
        }

        return actionObject.keys.sorted().compactMap { key in
            let value = actionObject[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        .joined(separator: "; ")
    }

    static func semanticActionValue(
        in object: [String: LLMActionValue],
        allowsTargetFields: Bool = false
    ) -> String? {
        for key in preferredObjectKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }

            if hasOnlyActionOrMetadataFields(object, allowsTargetFields: allowsTargetFields) {
                return value
            }
        }
        return nil
    }

    static func booleanFlagAction(
        in object: [String: LLMActionValue],
        allowsTargetFields: Bool = false
    ) -> String? {
        for key in booleanActionFlagKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text,
                  isTruthy(value),
                  hasOnlyActionOrMetadataFields(object, allowsTargetFields: allowsTargetFields) else {
                continue
            }
            return key
        }
        return nil
    }

    static func hasOnlyActionOrMetadataFields(
        _ object: [String: LLMActionValue],
        allowsTargetFields: Bool = false
    ) -> Bool {
        object.allSatisfy { objectKey, objectValue in
            let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.isEmpty
                || preferredObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                || booleanActionFlagKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                || (allowsTargetFields && targetObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame })
                || (allowsTargetFields && targetContainerKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame })
                || (allowsTargetFields && booleanTargetFlagKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame })
        }
    }

    static func targetValue(in object: [String: LLMTargetValue]) -> String {
        for key in targetObjectKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }
            return value
        }
        for key in booleanTargetFlagKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text,
                  isTruthy(value) else {
                continue
            }
            return key
        }
        for key in targetContainerKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }
            return value
        }
        return ""
    }

    static func targetedAction(_ action: String, target: String) -> String {
        guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return action
        }
        let normalizedTargetedAction = SpokenEditCommandLLMResolver.normalizedAction(action, target: target)
        return normalizedTargetedAction == normalizedIdentifier(action) ? action : normalizedTargetedAction
    }

    static func isTruthy(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        default:
            return false
        }
    }

    static func normalizedIdentifier(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

struct LLMTargetValue: Decodable, Equatable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            text = ""
        } else if let value = try? container.decode(String.self) {
            text = value
        } else if let value = try? container.decode(Bool.self) {
            text = value ? "true" : "false"
        } else if let value = try? container.decode([String: LLMTargetValue].self) {
            text = Self.describe(object: value)
        } else if let value = try? container.decode([LLMTargetValue].self) {
            text = Self.describe(array: value)
        } else {
            text = ""
        }
    }
}

private extension LLMTargetValue {
    static let preferredObjectKeys = [
        "target", "scope", "object", "subject", "kind", "type",
        "entity", "name", "value", "text", "selection",
        "targetText", "target_text", "editTarget", "edit_target",
    ]
    static let metadataObjectKeys = [
        "confidence", "score", "probability", "certainty", "reason", "rationale",
        "justification", "description", "explanation", "note", "notes",
    ]

    static func describe(array: [LLMTargetValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMTargetValue]) -> String {
        if let target = booleanFlagTarget(in: object) {
            return target
        }
        for key in preferredObjectKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }

            let hasOnlyTargetOrMetadata = object.allSatisfy { objectKey, objectValue in
                let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return candidate.isEmpty
                    || preferredObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                    || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
            }
            if hasOnlyTargetOrMetadata {
                return value
            }
        }
        return ""
    }

    static func booleanFlagTarget(in object: [String: LLMTargetValue]) -> String? {
        for key in LLMActionValue.booleanTargetFlagKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text,
                  LLMActionValue.isTruthy(value),
                  hasOnlyTargetOrMetadataFields(object) else {
                continue
            }
            return key
        }
        return nil
    }

    static func hasOnlyTargetOrMetadataFields(_ object: [String: LLMTargetValue]) -> Bool {
        object.allSatisfy { objectKey, objectValue in
            let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.isEmpty
                || preferredObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                || LLMActionValue.booleanTargetFlagKeys.contains {
                    $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame
                }
                || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
        }
    }
}
