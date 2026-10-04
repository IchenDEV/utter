import Foundation
import CoreGraphics
import UtterContracts

extension TextProcessor {
    /// Command mode: uses voice command system prompt, higher max tokens.
    package func processCommand(
        text: String,
        model: String,
        screenContext: String,
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil
    ) async -> String {
        let settings = snapshotSettings()
        var options = TextProcessingOptions(settings: settings)
        options.llmModel = model
        return await processCommand(
            text: text,
            options: options,
            screenContext: screenContext,
            screenImage: screenImage,
            memoryContext: memoryContext,
            inputContext: inputContext
        )
    }

    package func processCommand(
        text: String,
        options: TextProcessingOptions,
        screenContext: String,
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        dictionarySnapshot requestedDictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) async -> String {
        let options = await effectiveProviderOptions(options)
        let dictionarySnapshot = requestedDictionarySnapshot ?? snapshotDictionary()
        let useScreenImage = shouldUseScreenImage(options: options, image: screenImage)
        let baseUserPrompt = PromptBuilder.buildCommandUserPrompt(
            text: text,
            inputLanguage: options.inputLanguage
        )
        let assembly = commandAssembly(
            options: options,
            screenContext: screenContext,
            screenImageAvailable: useScreenImage,
            memoryContext: memoryContext,
            inputContext: inputContext,
            dictionarySnapshot: dictionarySnapshot,
            transcript: text
        )
        let userPrompt = assembly.userPrompt(containing: baseUserPrompt)

        do {
            var result: String
            if let screenImage, useScreenImage {
                result = try await withLocalModelAccess {
                    do {
                        return try await generateWithScreenImage(
                            prompt: userPrompt,
                            systemPrompt: assembly.stablePrefix,
                            model: options.llmModel,
                            image: screenImage,
                            maxTokens: 4096,
                            temperature: 0.3, providerID: options.imageProviderID, modelLocations: options.modelLocations
                        )
                    } catch {
                        try Task.checkCancellation()
                        log.error("[TextProcessor] Command VLM failed, falling back to text LLM: \(error.localizedDescription)")
                        let textFallback = commandAssembly(
                            options: options,
                            screenContext: screenContext,
                            screenImageAvailable: false,
                            memoryContext: memoryContext,
                            inputContext: inputContext,
                            dictionarySnapshot: dictionarySnapshot,
                            transcript: text
                        )
                        return try await generateText(
                            prompt: textFallback.userPrompt(containing: baseUserPrompt),
                            systemPrompt: textFallback.stablePrefix,
                            options: options,
                            maxTokens: 4096,
                            temperature: 0.3
                        )
                    }
                }
            } else {
                result = try await generateText(
                    prompt: userPrompt,
                    systemPrompt: assembly.stablePrefix,
                    options: options,
                    maxTokens: 4096,
                    temperature: 0.3
                )
            }

            return cleanCommandGeneratedOutput(result, inputLanguage: options.inputLanguage)
        } catch {
            log.error("[TextProcessor] Command LLM failed: \(error.localizedDescription)")
            return ""
        }
    }

}
