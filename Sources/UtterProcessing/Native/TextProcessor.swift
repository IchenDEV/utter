import UtterMediaContracts
import UtterContracts
import CoreGraphics
import Foundation

package final class TextProcessor {
    package static let defaultAllowsPreparedFallback = false
    @TaskLocal package static var espressoGenerationTracker: EspressoGenerationTracker?

    package let providers: any ProviderCatalog<GenerationPurpose, any TextGenerationService>
    package let imageProviders: (any ProviderCatalog<GenerationPurpose, any ImageGenerationService>)?
    let localModelAccessGate: any ModelResourceAccess
    let modelFiles: any ModelFilesService
    let snapshotSettings: () -> SettingsValues
    let snapshotDictionary: () -> PersonalDictionarySnapshot
    let log: Log

    package init(
        providers: any ProviderCatalog<GenerationPurpose, any TextGenerationService>,
        imageProviders: (any ProviderCatalog<GenerationPurpose, any ImageGenerationService>)?,
        access: any ModelResourceAccess, files: any ModelFilesService,
        settings: @escaping () -> SettingsValues, dictionary: @escaping () -> PersonalDictionarySnapshot,
        log: Log
    ) {
        self.providers = providers
        self.imageProviders = imageProviders
        localModelAccessGate = access
        modelFiles = files
        snapshotSettings = settings
        snapshotDictionary = dictionary
        self.log = log
    }

    package func basicClean(
        text: String,
        inputLanguage: InputLanguage = .auto,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) -> String {
        let snapshot = dictionarySnapshot ?? snapshotDictionary()
        var result = snapshot.applyReplacements(to: text)
        result = normalizeWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package func prepareForFormatting(
        text: String,
        inputLanguage: InputLanguage,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) -> String {
        let snapshot = dictionarySnapshot ?? snapshotDictionary()
        var result = snapshot.applyReplacements(to: text)
        result = TranscriptionSanitizer.normalizeInput(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package func process(
        text: String,
        stylePrompt: String,
        model: String,
        screenContext: String = "",
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        formatKind: TextFormatKind? = nil,
        allowsPreparedFallback: Bool = TextProcessor.defaultAllowsPreparedFallback
    ) async -> String {
        let settings = snapshotSettings()
        var options = TextProcessingOptions(settings: settings)
        options.customStylePrompt = stylePrompt
        options.llmModel = model
        return await process(
            text: text,
            options: options,
            screenContext: screenContext,
            screenImage: screenImage,
            memoryContext: memoryContext,
            inputContext: inputContext,
            formatKind: formatKind,
            allowsPreparedFallback: allowsPreparedFallback
        )
    }

    package func process(
        text: String,
        options: TextProcessingOptions,
        screenContext: String = "",
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        formatKind: TextFormatKind? = nil,
        allowsPreparedFallback: Bool = TextProcessor.defaultAllowsPreparedFallback,
        dictionarySnapshot requestedDictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) async -> String {
        let options = await effectiveProviderOptions(options)
        let prepareStarted = CFAbsoluteTimeGetCurrent()
        let dictionarySnapshot = requestedDictionarySnapshot ?? snapshotDictionary()
        let cleanedText = prepareForFormatting(
            text: text,
            inputLanguage: options.inputLanguage,
            dictionarySnapshot: dictionarySnapshot
        )
        let prepareElapsed = CFAbsoluteTimeGetCurrent() - prepareStarted
        log.info("[TextProcessor] prepared LLM input \(text.count) chars to \(cleanedText.count) chars in \(String(format: "%.2f", prepareElapsed))s")
        guard !cleanedText.isEmpty else { return "" }

        let useScreenImage = shouldUseScreenImage(options: options, image: screenImage)
        let baseUserPrompt = formattingUserPrompt(
            text: cleanedText,
            options: options
        )
        let assembly = formattingAssembly(
            options: options,
            screenContext: screenContext,
            screenImageAvailable: useScreenImage,
            memoryContext: memoryContext,
            inputContext: inputContext,
            formatKind: formatKind,
            dictionarySnapshot: dictionarySnapshot,
            transcript: cleanedText
        )
        let userPrompt = assembly.userPrompt(containing: baseUserPrompt)

        let generationOptions = formattingOptions(for: cleanedText, style: options.languageStyle)

        do {
            var result: String
            let llmStarted = CFAbsoluteTimeGetCurrent()
            if let screenImage, useScreenImage {
                result = try await withLocalModelAccess {
                    do {
                        return try await generateWithScreenImage(
                            prompt: userPrompt,
                            systemPrompt: assembly.stablePrefix,
                            model: options.llmModel,
                            image: screenImage,
                            maxTokens: generationOptions.maxTokens,
                            temperature: generationOptions.temperature, providerID: options.imageProviderID,
                            modelLocations: options.modelLocations, modelVersions: options.modelVersions
                        )
                    } catch {
                        try Task.checkCancellation()
                        log.error("[TextProcessor] VLM failed, falling back to text LLM: \(error.localizedDescription)")
                        let textFallback = formattingAssembly(
                            options: options,
                            screenContext: screenContext,
                            screenImageAvailable: false,
                            memoryContext: memoryContext,
                            inputContext: inputContext,
                            formatKind: formatKind,
                            dictionarySnapshot: dictionarySnapshot,
                            transcript: cleanedText
                        )
                        return try await generateText(
                            prompt: textFallback.userPrompt(containing: baseUserPrompt),
                            systemPrompt: textFallback.stablePrefix,
                            options: options,
                            maxTokens: generationOptions.maxTokens,
                            temperature: generationOptions.temperature
                        )
                    }
                }
            } else {
                result = try await generateText(
                    prompt: userPrompt,
                    systemPrompt: assembly.stablePrefix,
                    options: options,
                    maxTokens: generationOptions.maxTokens,
                    temperature: generationOptions.temperature
                )
            }
            let llmElapsed = CFAbsoluteTimeGetCurrent() - llmStarted
            log.info("[TextProcessor] formatting LLM completed in \(String(format: "%.2f", llmElapsed))s with budget \(generationOptions.maxTokens) tokens")

            let fallback = allowsPreparedFallback ? cleanedText : ""
            let output = cleanGeneratedOutput(
                result,
                inputLanguage: options.inputLanguage,
                fallback: fallback
            )
            return validatedOutput(
                output, source: cleanedText,
                protectedTerms: dictionarySnapshot.protectedTerms,
                inputLanguage: options.inputLanguage,
                enforceSemanticFidelity: options.fidelityPolicy == .faithfulCorrection
            )
        } catch {
            if Task.isCancelled { return "" }
            if allowsPreparedFallback {
                log.error("[TextProcessor] LLM failed, falling back to prepared raw text: \(error.localizedDescription)")
                return cleanedText
            }
            log.error("[TextProcessor] LLM failed with prepared fallback disabled: \(error.localizedDescription)")
            return ""
        }
    }

}
