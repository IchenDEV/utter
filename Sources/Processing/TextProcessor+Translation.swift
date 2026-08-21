import Foundation

extension TextProcessor {
    func translate(
        text: String,
        targetLanguage: TranslationLanguage,
        options: TextProcessingOptions
    ) async -> String {
        let prepared = prepareForFormatting(text: text, inputLanguage: options.inputLanguage)
        guard !prepared.isEmpty else { return "" }

        let systemPrompt = PromptCatalog.translationSystemPrompt(
            targetLanguage: targetLanguage,
            inputLanguage: options.inputLanguage
        )
        let userPrompt = PromptCatalog.translationUserPrompt(
            text: prepared,
            targetLanguage: targetLanguage
        )
        let maxTokens = min(
            max(256, prepared.count * 3),
            ProductEdition.current.maximumGenerationTokens
        )

        do {
            let result = try await generateText(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                options: options,
                maxTokens: maxTokens,
                temperature: 0
            )
            return cleanCommandGeneratedOutput(result, inputLanguage: options.inputLanguage)
        } catch {
            Log.error("[TextProcessor] translation failed: \(error.localizedDescription)")
            return ""
        }
    }
}
