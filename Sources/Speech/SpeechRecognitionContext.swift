import Foundation

struct SpeechRecognitionContext: Equatable, Sendable {
    static let empty = SpeechRecognitionContext(phrases: [])
    static let maximumPhraseCount = 100

    let phrases: [String]

    init(phrases: [String]) {
        var seen = Set<String>()
        let normalizedPhrases: [String] = phrases.compactMap { phrase -> String? in
            let normalized = phrase
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 80 else { return nil }
            guard seen.insert(normalized.lowercased()).inserted else { return nil }
            return normalized
        }
        self.phrases = Array(normalizedPhrases.prefix(Self.maximumPhraseCount))
    }

    init(dictionaryEntries: [DictionaryEntry]) {
        let ranked = dictionaryEntries.enumerated().sorted { lhs, rhs in
            if lhs.element.origin != rhs.element.origin {
                return lhs.element.origin == .manual
            }
            if lhs.element.origin == .manual {
                return lhs.offset < rhs.offset
            }
            if lhs.element.evidenceCount != rhs.element.evidenceCount {
                return lhs.element.evidenceCount > rhs.element.evidenceCount
            }
            let lhsDate = lhs.element.lastSeenAt ?? lhs.element.createdAt
            let rhsDate = rhs.element.lastSeenAt ?? rhs.element.createdAt
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.offset < rhs.offset
        }.map(\.element)
        self.init(phrases: ranked.compactMap { entry -> String? in
            guard entry.isEffective else { return nil }
            let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            return replacement.isEmpty ? nil : replacement
        })
    }

    func whisperPrompt(language: String?) -> String? {
        let terms = phrases.joined(separator: ", ")
        switch (language, terms.isEmpty) {
        case ("zh", true):
            return "以下是普通话听写。"
        case ("zh", false):
            return "以下是普通话听写。专有名词：\(terms)。"
        case ("yue", true):
            return "以下是粤语听写。"
        case ("yue", false):
            return "以下是粤语听写。专有名词：\(terms)。"
        case ("ja", false):
            return "音声入力。固有名詞：\(terms)。"
        case ("ko", false):
            return "음성 받아쓰기. 고유 명사: \(terms)."
        case ("en", false):
            return "Dictation. Terms: \(terms)."
        case (_, false):
            return "Dictation terms: \(terms)."
        default:
            return nil
        }
    }

    func whisperPromptTokens(
        language: String?,
        maximumCount: Int,
        tokenize: (String) -> [Int]
    ) -> [Int]? {
        guard maximumCount > 0 else { return nil }
        var acceptedPhrases: [String] = []
        var bestTokens = SpeechRecognitionContext(phrases: [])
            .whisperPrompt(language: language)
            .map(tokenize)
            .flatMap { $0.count <= maximumCount ? $0 : nil }

        for phrase in phrases {
            let candidatePhrases = acceptedPhrases + [phrase]
            guard let prompt = SpeechRecognitionContext(phrases: candidatePhrases)
                .whisperPrompt(language: language) else {
                continue
            }
            let tokens = tokenize(prompt)
            if tokens.count <= maximumCount {
                acceptedPhrases = candidatePhrases
                bestTokens = tokens
            }
        }
        return bestTokens
    }
}
