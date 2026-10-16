import Foundation
import UtterContracts

extension TextProcessor {
    package func processSelectionEdit(selectedText: String, intent: SelectionRewriteIntent,
        options: TextProcessingOptions, spokenCommand: String = "", memoryContext: String = "",
        inputContext: InputContext? = nil, dictionarySnapshot: PersonalDictionarySnapshot? = nil) async -> String {
        let options = await effectiveProviderOptions(options)
        do {
            return try await SelectionEditRecipe.candidate(selectedText: selectedText, intent: intent,
                inputLanguage: options.inputLanguage, spokenCommand: spokenCommand, memoryContext: memoryContext,
                inputContext: inputContext, dictionarySnapshot: dictionarySnapshot ?? snapshotDictionary()) { prompt, system, budget in
                    try await self.generateText(prompt: prompt, systemPrompt: system, options: options,
                        maxTokens: budget.maxTokens, temperature: budget.temperature, allowsFailureDetails: false)
                }
        } catch {
            log.error("[TextProcessor] Selection edit failed")
            return ""
        }
    }
}
