import Foundation
import UtterContracts

package enum SelectionEditRecipe {
    package enum Failure: Error, Equatable { case emptySelection, emptyInstruction, emptyCandidate }

    package static func candidate(selectedText: String, intent: SelectionRewriteIntent,
        inputLanguage: InputLanguage, spokenCommand: String = "", memoryContext: String = "",
        inputContext: InputContext? = nil, dictionarySnapshot: PersonalDictionarySnapshot? = nil,
        generate: (String, String, GenerationOptions) async throws -> String) async throws -> String {
        try Task.checkCancellation()
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.emptySelection }
        if case .custom(let instruction) = intent, instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw Failure.emptyInstruction
        }
        let base = selectionEditPrompt(selectedText: selectedText, intent: intent, inputLanguage: inputLanguage,
            spokenCommand: spokenCommand, memoryContext: memoryContext, inputContext: inputContext)
        let personal = dictionarySnapshot.map { snapshot in
            [PromptCatalog.activeIndustryLexiconSection(snapshot.industryLexicon.promptDescription(matching: selectedText),
                industry: snapshot.industryLexicon.pack?.id, inputLanguage: inputLanguage),
             PromptCatalog.activePersonalDictionarySection(snapshot.activeEntriesDescription, inputLanguage: inputLanguage),
             PromptCatalog.activeEditRulesSection(snapshot.activeRulesDescription, inputLanguage: inputLanguage)].compactMap { $0 }
        } ?? []
        let prompt = personal.isEmpty ? base : personal.joined(separator: "\n\n") + "\n\n" + base
        let output = try await LLMFinalTextOutput.$requiresExplicitFinalText.withValue(true) {
            try await generate(prompt, selectionEditSystemPrompt(inputLanguage: inputLanguage),
                selectionEditOptions(for: selectedText, intent: intent))
        }
        try Task.checkCancellation()
        let candidate = normalize(output)
        guard !candidate.isEmpty else { throw Failure.emptyCandidate }
        return candidate
    }

    package static func normalize(_ output: String) -> String {
        LLMFinalTextOutput.$requiresExplicitFinalText.withValue(true) {
            let text = GeneratedOutputNormalizer.stripThinkingTags(output)
            let structured = FormattedOutputCleaner.clean(text)
            if let data = structured.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                guard let final = LLMFinalTextOutput.text(from: structured) else { return "" }
                return CommandOutputCleaner.clean(final)
            }
            return CommandOutputCleaner.clean(text)
        }
    }
}
