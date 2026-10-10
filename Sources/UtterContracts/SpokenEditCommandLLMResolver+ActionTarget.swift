import Foundation

extension SpokenEditCommandLLMResolver {
    package static func normalizedAction(_ rawAction: String?, target rawTarget: String?) -> String {
        let action = normalizedCommandIdentifier(rawAction)
        switch action {
        case "replace", "rewrite":
            let target = normalizedEditTarget(rawTarget)
            return target.isEmpty ? action : "\(action)_\(target)"
        case "delete" where normalizedEditTarget(rawTarget) == "selection":
            return "delete_selection"
        case "undo" where normalizedEditTarget(rawTarget) == "last":
            return "undo_last_insertion"
        default:
            return action
        }
    }

    package static func normalizedEditTarget(_ rawTarget: String?) -> String {
        switch normalizedCommandIdentifier(rawTarget) {
        case "last", "previous", "last_insertion", "previous_insertion",
             "lastinsertion", "previousinsertion",
             "lastinsertedtext", "last_inserted_text",
             "last_output", "lastoutput":
            return "last"
        case "selection", "selected", "selected_text", "current_selection":
            return "selection"
        case "selectedtext", "currentselection", "active_selection", "activeselection":
            return "selection"
        default:
            return ""
        }
    }
}

private func normalizedCommandIdentifier(_ rawValue: String?) -> String {
    (rawValue ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
}
