import Foundation

package enum SpeechArtifactPolicy {
    package static func isNonSpeechArtifact(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if explicitNoSpeechArtifacts.contains(trimmed.lowercased()) { return true }

        let meaningfulScalars = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
        if meaningfulScalars.isEmpty { return true }

        let cleaned = normalizedPhrase(trimmed)
        return cleaned.isEmpty || noSpeechArtifacts.contains(cleaned)
    }

    package static func normalizedPhrase(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }))
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    }

    private static let noSpeechArtifacts: Set<String> = [
        "blankaudio",
        "nospeech",
    ]

    private static let explicitNoSpeechArtifacts: Set<String> = [
        "(无)", "（无）", "[无]", "【无】",
        "(無)", "（無）", "[無]", "【無】",
        "(silence)", "[silence]", "<silence>",
        "(silent)", "[silent]", "<silent>",
        "(blank audio)", "[blank audio]", "<blank audio>",
        "(no speech)", "[no speech]", "<no speech>",
        "[blank_audio]", "<blank_audio>",
    ]

}
