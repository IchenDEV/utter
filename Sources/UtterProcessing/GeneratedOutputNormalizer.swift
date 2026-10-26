import Foundation
import UtterContracts

package enum GeneratedOutputNormalizer {
    private static let thinkTagNames = [
        "analysis",
        "think", "thinking", "thought",
        "reason", "reasoning",
        "reflect", "reflection",
        "inner_monologue", "scratchpad",
    ]

    private static let thinkTagPattern: String = {
        let names = thinkTagNames.joined(separator: "|")
        return "<(?:\(names))(?:\\s+[^>]*)?>"
    }()

    package static func stripThinkingTags(_ text: String) -> String {
        if let finalText = LLMScaffoldedOutput.finalText(from: text) {
            return finalText
        }

        var result = text
        for tag in Self.thinkTagNames {
            result = result.replacingOccurrences(
                of: "<\(tag)(?:\\s+[^>]*)?>[\\s\\S]*?</\(tag)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(
            of: "\(Self.thinkTagPattern)[\\s\\S]*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func commandText(_ text: String) -> String {
        CommandOutputCleaner.clean(stripThinkingTags(text))
    }
}
