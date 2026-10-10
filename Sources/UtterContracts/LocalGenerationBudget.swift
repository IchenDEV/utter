import Foundation

package enum LocalGenerationBudget {
    package static func contextLimit(configuration: Data) throws -> Int? {
        guard let object = try JSONSerialization.jsonObject(with: configuration) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let text = object["text_config"] as? [String: Any] ?? object
        for key in ["max_position_embeddings", "max_sequence_length", "n_positions", "seq_length"] {
            if let value = text[key] {
                guard let number = value as? Int, number > 0 else { throw CocoaError(.fileReadCorruptFile) }
                return number
            }
        }
        return nil
    }

    package static func allows(inputTokens: Int, outputTokens: Int, contextLimit: Int?) -> Bool {
        guard inputTokens >= 0, outputTokens > 0 else { return false }
        guard let contextLimit else { return true }
        return outputTokens <= contextLimit && inputTokens <= contextLimit - outputTokens
    }
}
