import Foundation

package struct EditRule: Codable, Identifiable, Sendable {
    package var id = UUID()
    package var description: String
    package var enabled: Bool = true

    package init(id: UUID = UUID(), description: String, enabled: Bool = true) {
        self.id = id
        self.description = description
        self.enabled = enabled
    }
}

package struct PersonalDictionarySnapshot: Sendable {
    package let entries: [DictionaryEntry]
    package let editRules: [EditRule]
    package let industryLexicon: IndustryLexiconSnapshot

    package init(
        entries: [DictionaryEntry],
        editRules: [EditRule],
        industryLexicon: IndustryLexiconSnapshot = .empty,
        bundleIdentifier: String? = nil,
        languageCode: String? = nil
    ) {
        self.entries = entries.filter {
            $0.applies(bundleIdentifier: bundleIdentifier, languageCode: languageCode)
        }
        self.editRules = editRules
        self.industryLexicon = industryLexicon
    }

    package func applyReplacements(to text: String) -> String {
        let personalRules = entries.enumerated().compactMap { offset, entry -> VocabularyReplacementRule? in
            let original = entry.original
            let replacement = entry.replacement
            guard entry.isEffective,
                  !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return VocabularyReplacementRule(
                original: original,
                replacement: replacement,
                sourcePriority: 0,
                insertionOrder: offset
            )
        }

        let industryRules = industryLexicon.corrections.enumerated().map { offset, correction in
            VocabularyReplacementRule(
                original: correction.recognized,
                replacement: correction.preferred,
                sourcePriority: 1,
                insertionOrder: offset
            )
        }

        return VocabularyReplacementEngine.apply(personalRules + industryRules, to: text)
    }

    package var activeEntriesDescription: String {
        entries
            .filter(\.isEffective)
            .compactMap { entry -> String? in
                let original = entry.original.trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !original.isEmpty, !replacement.isEmpty else { return nil }
                return "\(original) -> \(replacement)"
            }
            .joined(separator: "\n")
    }

    package var activeRulesDescription: String {
        editRules
            .filter(\.enabled)
            .map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    package var personalRecognitionPhrases: [String] {
        SpeechRecognitionContext(dictionaryEntries: entries).phrases
    }

    package var recognitionPhrases: [String] {
        return SpeechRecognitionContext(
            phrases: personalRecognitionPhrases + industryLexicon.recognitionPhrases
        ).phrases
    }

    package var protectedTerms: [String] {
        var seen = Set<String>()
        let personalTerms = entries.compactMap { entry -> String? in
            guard entry.isEffective else { return nil }
            let term = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty,
                  seen.insert(term.lowercased()).inserted else {
                return nil
            }
            return term
        }
        let industryTerms = industryLexicon.protectedTerms.compactMap { term -> String? in
            guard seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }
        return industryTerms + personalTerms
    }
}

