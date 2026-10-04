import UtterContracts
import Foundation

extension TextProcessor {
    package func translate(
        text: String,
        targetLanguage: TranslationLanguage,
        options: TextProcessingOptions,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) async -> String {
        let options = await effectiveProviderOptions(options)
        let prepared = prepareForFormatting(text: text, inputLanguage: options.inputLanguage, dictionarySnapshot: dictionarySnapshot)
        guard !prepared.isEmpty else { return "" }

        let systemPrompt = PromptCatalog.translationSystemPrompt(
            targetLanguage: targetLanguage,
            inputLanguage: options.inputLanguage
        )
        let userPrompt = PromptCatalog.translationUserPrompt(
            text: prepared,
            targetLanguage: targetLanguage
        )
        let maxTokens = min(max(256, prepared.count * 3), 4_096)

        do {
            let result = try await generateText(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                options: options,
                maxTokens: maxTokens,
                temperature: 0.1
            )
            return cleanCommandGeneratedOutput(result, inputLanguage: options.inputLanguage)
        } catch {
            log.error("[TextProcessor] translation failed: \(error.localizedDescription)")
            return ""
        }
    }
}
