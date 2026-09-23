import Foundation

struct QwenRecognitionPrompt: Sendable {
    static let maximumPhrases = 8
    static let maximumTermsLength = 160

    let phrases: [String]
    let text: String

    init(phrases: [String]) {
        var accepted: [String] = []
        var seen = Set<String>()
        for raw in phrases {
            let phrase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, phrase.count <= 80,
                  seen.insert(phrase.lowercased()).inserted else { continue }
            let proposed = (accepted + [phrase]).joined(separator: ", ")
            guard accepted.count < Self.maximumPhrases else { break }
            guard proposed.count <= Self.maximumTermsLength else { continue }
            accepted.append(phrase)
        }
        self.phrases = accepted
        text = accepted.isEmpty ? "" : "Vocabulary: \(accepted.joined(separator: ", "))."
    }
}

enum QwenPromptEcho {
    static func matches(_ transcript: String, prompt: QwenRecognitionPrompt) -> Bool {
        guard !prompt.text.isEmpty else { return false }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if lowered.hasPrefix("vocabulary:") || lowered.hasPrefix("terms:") { return true }

        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let segments = text.components(separatedBy: CharacterSet(charactersIn: ",，、;；\n"))
            .map { $0.trimmingCharacters(in: trim).lowercased() }
            .filter { !$0.isEmpty }
        guard segments.count >= 4 else { return false }
        let expected = prompt.phrases.map { $0.trimmingCharacters(in: trim).lowercased() }
        guard expected.count >= 4 else { return false }
        for expectedStart in 0...(expected.count - 4) {
            for transcriptStart in 0...(segments.count - 4) {
                if Array(segments[transcriptStart..<(transcriptStart + 4)])
                    == Array(expected[expectedStart..<(expectedStart + 4)]) {
                    return true
                }
            }
        }
        return false
    }
}

enum QwenContextRecovery {
    static func run<Result>(
        prompt: QwenRecognitionPrompt,
        recognize: (String) async throws -> Result,
        text: (Result) -> String
    ) async throws -> Result? {
        let first = try await recognize(prompt.text)
        guard QwenPromptEcho.matches(text(first), prompt: prompt) else { return first }
        let retry = try await recognize("")
        return QwenPromptEcho.matches(text(retry), prompt: prompt) ? nil : retry
    }
}
