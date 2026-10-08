import UtterContracts
import Foundation

extension TextProcessor {
    package func resolveSpokenEditCommand(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) async -> SpokenEditCommand? {
        guard case .command(let command) = await resolveSpokenEditCommandResolution(
            text: text,
            options: options,
            context: context,
            dictionarySnapshot: dictionarySnapshot
        ) else {
            return nil
        }
        return command
    }

    package func resolveSpokenEditCommandResolution(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
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
                dictionarySnapshot: dictionarySnapshot,
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
            if case .command(let command) = resolution {
                guard SpokenEditEvidence.allows(command, transcript: transcript, context: context) else {
                    return .some(.none)
                }
                log.info("[TextProcessor] LLM resolved a spoken edit command")
            }
            return resolution
        } catch {
            log.error("[TextProcessor] LLM edit command resolution failed: \(error.localizedDescription)")
            return nil
        }
    }

    package func editCommandResolutionOptions(for text: String) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maxTokens = characterCount > 160 ? 384 : 256
        return GenerationOptions(maxTokens: maxTokens, temperature: 0)
    }
}
