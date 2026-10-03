import UtterProcessing
import UtterContracts
import Foundation

extension TextProcessor {
    func resolveSpokenEditCommand(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown
    ) async -> SpokenEditCommand? {
        guard case .command(let command) = await resolveSpokenEditCommandResolution(
            text: text,
            options: options,
            context: context
        ) else {
            return nil
        }
        return command
    }

    func resolveSpokenEditCommandResolution(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown
    ) async -> SpokenEditCommandLLMResolution? {
        let transcript = TranscriptionSanitizer.normalizeInput(text)
        guard !transcript.isEmpty else { return nil }

        do {
            let generationOptions = editCommandResolutionOptions(for: transcript)
            let baseUserPrompt = PromptBuilder.buildEditCommandResolverUserPrompt(
                text: transcript,
                inputLanguage: options.inputLanguage,
                context: context
            )
            let personal = personalContextSections(
                inputLanguage: options.inputLanguage,
                transcript: transcript
            )
            let userPrompt = personal.isEmpty
                ? baseUserPrompt
                : personal.joined(separator: "\n\n") + "\n\n" + baseUserPrompt
            let result = try await generateText(
                prompt: userPrompt,
                systemPrompt: PromptBuilder.buildEditCommandResolverSystemPrompt(
                    inputLanguage: options.inputLanguage
                ),
                options: options,
                maxTokens: generationOptions.maxTokens,
                temperature: generationOptions.temperature
            )
            let resolution = SpokenEditCommandLLMResolver.resolution(from: result)
            if case .command = resolution {
                Log.info("[TextProcessor] LLM resolved a spoken edit command")
            }
            return resolution
        } catch {
            Log.error("[TextProcessor] LLM edit command resolution failed: \(error.localizedDescription)")
            return nil
        }
    }

    func editCommandResolutionOptions(for text: String) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maxTokens = characterCount > 160 ? 384 : 256
        return GenerationOptions(maxTokens: maxTokens, temperature: 0)
    }
}
