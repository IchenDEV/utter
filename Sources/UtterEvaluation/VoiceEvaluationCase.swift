import Foundation
import UtterContracts

package struct VoiceEvaluationCase: Codable, Sendable {
    package let id: String
    package let language: String
    package let faithful_reference: String
    package let sendable_reference: String?
    package let input_text: String?
    package let audio_file: String?
    package let mode: String?
    package let style: String?
    package let custom_style_prompt: String?
    package let target_language: String?
    package let lexicon: String?
    package let screen_context: String?
    package let edit_rules: [String]?
    package let supplied_candidate: String?
    package let terms: [String]?
    package let forbidden_terms: [String]?
    package let expected_outcome: String?
    package let repetitions: Int?

    package var text: String { input_text ?? faithful_reference }
    package var repeatCount: Int { repetitions ?? 1 }

    package static func load(_ data: Data, maximumRuns: Int) throws -> [Self] {
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        var cases: [Self] = []
        var ids = Set<String>()
        var runs = 0
        for line in lines {
            let value = try JSONDecoder().decode(Self.self, from: Data(line.utf8))
            guard !value.id.isEmpty, ids.insert(value.id).inserted,
                  ["zh", "zh-Hans", "zh-Hant", "en", "ja", "ko", "yue", "auto"].contains(value.language),
                  ["formatting", "direct", "command", "translation"].contains(value.mode ?? "formatting"),
                  ["casual", "professional", "custom"].contains(value.style ?? "casual"),
                  value.lexicon == nil || IndustryLexiconID(rawValue: value.lexicon!) != nil,
                  value.target_language == nil || TranslationLanguage(rawValue: value.target_language!) != nil,
                  value.expected_outcome == nil || ProcessingDecision.Disposition(rawValue: value.expected_outcome!) != nil,
                  value.audio_file == nil || !value.audio_file!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.repeatCount > 0, value.repeatCount <= maximumRuns,
                  value.audio_file == nil || value.input_text == nil else {
                throw VoiceEvaluationError.invalidCase(value.id)
            }
            if value.mode == "translation", value.target_language == nil {
                throw VoiceEvaluationError.invalidCase(value.id)
            }
            runs += value.repeatCount
            guard runs <= maximumRuns else { throw VoiceEvaluationError.runBudgetExceeded }
            cases.append(value)
        }
        guard !cases.isEmpty else { throw VoiceEvaluationError.emptyCorpus }
        return cases
    }
}

package enum VoiceEvaluationError: Error, CustomStringConvertible {
    case invalidCase(String), emptyCorpus, runBudgetExceeded, tokenBudgetExceeded, timedOut, invalidArguments(String), unavailableAudioProvider

    package var description: String {
        switch self {
        case .invalidCase(let id): return "Invalid evaluation case: \(id)"
        case .emptyCorpus: return "Evaluation corpus is empty"
        case .runBudgetExceeded: return "Requested corpus exceeds the run budget"
        case .tokenBudgetExceeded: return "Evaluation output-token budget exceeded"
        case .timedOut: return "Evaluation time budget exceeded"
        case .invalidArguments(let detail): return "Invalid evaluation arguments: \(detail)"
        case .unavailableAudioProvider: return "Audio evaluation requires an explicitly selected installed speech model"
        }
    }
}
