import CoreGraphics
import Foundation

final class TextProcessor {
    static let defaultAllowsPreparedFallback = false

    let llm = LLMEngine()
    let vlm = VLMEngine()
    let remoteLLMClient = RemoteLLMClient()
    private let dictionary = PersonalDictionary.shared
    var isLLMReady: Bool {
        get async {
            if AppSettings.shared.useRemoteLLM { return true }
            return await llm.isLoaded
        }
    }

    func unloadLLM() async {
        await llm.unload()
        await vlm.unload()
    }

    @discardableResult
    func warmUpLLM(model: String) async -> Bool {
        if AppSettings.shared.useRemoteLLM { return true }
        do {
            try await llm.loadModel(id: model)
            return true
        } catch {
            Log.error("[TextProcessor] LLM warmup failed: \(error.localizedDescription)")
            return false
        }
    }

    func basicClean(
        text: String,
        inputLanguage: InputLanguage = .auto,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) -> String {
        let snapshot = dictionarySnapshot ?? dictionary.snapshot()
        var result = snapshot.applyReplacements(to: text)
        result = normalizeWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prepareForFormatting(
        text: String,
        inputLanguage: InputLanguage,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) -> String {
        let snapshot = dictionarySnapshot ?? dictionary.snapshot()
        var result = snapshot.applyReplacements(to: text)
        result = TranscriptionSanitizer.normalizeInput(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func process(
        text: String,
        stylePrompt: String,
        model: String,
        screenContext: String = "",
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        formatKind: TextFormatKind? = nil,
        allowsPreparedFallback: Bool = TextProcessor.defaultAllowsPreparedFallback,
        allowsGuardFallback: Bool = true
    ) async -> String {
        let settings = AppSettings.shared
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
            allowsPreparedFallback: allowsPreparedFallback,
            allowsGuardFallback: allowsGuardFallback
        )
    }

    func process(
        text: String,
        options: TextProcessingOptions,
        screenContext: String = "",
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        formatKind: TextFormatKind? = nil,
        allowsPreparedFallback: Bool = TextProcessor.defaultAllowsPreparedFallback,
        allowsGuardFallback: Bool = true,
        dictionarySnapshot requestedDictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) async -> String {
        let prepareStarted = CFAbsoluteTimeGetCurrent()
        let dictionarySnapshot = requestedDictionarySnapshot ?? dictionary.snapshot()
        let cleanedText = prepareForFormatting(
            text: text,
            inputLanguage: options.inputLanguage,
            dictionarySnapshot: dictionarySnapshot
        )
        let prepareElapsed = CFAbsoluteTimeGetCurrent() - prepareStarted
        Log.info("[TextProcessor] prepared LLM input \(text.count) chars to \(cleanedText.count) chars in \(String(format: "%.2f", prepareElapsed))s")
        guard !cleanedText.isEmpty else { return "" }

        let useScreenImage = shouldUseScreenImage(options: options, image: screenImage)
        let systemPrompt = formattingSystemPrompt(
            options: options,
            screenContext: screenContext,
            screenImageAvailable: useScreenImage,
            memoryContext: memoryContext,
            inputContext: inputContext,
            formatKind: formatKind,
            dictionarySnapshot: dictionarySnapshot
        )

        let userPrompt = formattingUserPrompt(
            text: cleanedText,
            options: options
        )
        let generationOptions = formattingOptions(for: cleanedText, style: options.languageStyle)

        do {
            var result: String
            let llmStarted = CFAbsoluteTimeGetCurrent()
            if let screenImage, useScreenImage {
                do {
                    result = try await generateWithScreenImage(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
                        model: options.llmModel,
                        image: screenImage,
                        maxTokens: generationOptions.maxTokens,
                        temperature: generationOptions.temperature
                    )
                } catch {
                    Log.error("[TextProcessor] VLM failed, falling back to text LLM: \(error.localizedDescription)")
                    let textFallbackSystemPrompt = formattingSystemPrompt(
                        options: options,
                        screenContext: screenContext,
                        screenImageAvailable: false,
                        memoryContext: memoryContext,
                        inputContext: inputContext,
                        formatKind: formatKind,
                        dictionarySnapshot: dictionarySnapshot
                    )
                    result = try await generateText(
                        prompt: userPrompt,
                        systemPrompt: textFallbackSystemPrompt,
                        options: options,
                        maxTokens: generationOptions.maxTokens,
                        temperature: generationOptions.temperature
                    )
                }
            } else {
                result = try await generateText(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    options: options,
                    maxTokens: generationOptions.maxTokens,
                    temperature: generationOptions.temperature
                )
            }
            let llmElapsed = CFAbsoluteTimeGetCurrent() - llmStarted
            Log.info("[TextProcessor] formatting LLM completed in \(String(format: "%.2f", llmElapsed))s with budget \(generationOptions.maxTokens) tokens")

            let fallback = allowsPreparedFallback ? cleanedText : ""
            let output = cleanGeneratedOutput(
                result,
                inputLanguage: options.inputLanguage,
                fallback: fallback
            )
            if let violation = TranscriptFidelityGuard.violation(
                source: cleanedText,
                candidate: output,
                protectedTerms: dictionarySnapshot.protectedTerms,
                inputLanguage: options.inputLanguage,
                enforceSemanticFidelity: options.fidelityPolicy == .faithfulCorrection
            ) {
                Log.error("[TextProcessor] rejected unsafe formatting output: \(violation)")
                return rejectedOutputFallback(
                    cleanedText,
                    allowsGuardFallback: allowsGuardFallback
                )
            }
            return output
        } catch {
            if allowsPreparedFallback {
                Log.error("[TextProcessor] LLM failed, falling back to prepared raw text: \(error.localizedDescription)")
                return cleanedText
            }
            Log.error("[TextProcessor] LLM failed with prepared fallback disabled: \(error.localizedDescription)")
            return ""
        }
    }

    /// Command mode: uses voice command system prompt, higher max tokens.
    func processCommand(
        text: String,
        model: String,
        screenContext: String,
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil
    ) async -> String {
        let settings = AppSettings.shared
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

    func processCommand(
        text: String,
        options: TextProcessingOptions,
        screenContext: String,
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        dictionarySnapshot requestedDictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) async -> String {
        let dictionarySnapshot = requestedDictionarySnapshot ?? dictionary.snapshot()
        let useScreenImage = shouldUseScreenImage(options: options, image: screenImage)
        let systemPrompt = commandSystemPrompt(
            options: options,
            screenContext: screenContext,
            screenImageAvailable: useScreenImage,
            memoryContext: memoryContext,
            inputContext: inputContext,
            dictionarySnapshot: dictionarySnapshot
        )
        let userPrompt = PromptBuilder.buildCommandUserPrompt(
            text: text,
            inputLanguage: options.inputLanguage
        )

        do {
            var result: String
            if let screenImage, useScreenImage {
                do {
                    result = try await generateWithScreenImage(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
                        model: options.llmModel,
                        image: screenImage,
                        maxTokens: 4096,
                        temperature: 0.3
                    )
                } catch {
                    Log.error("[TextProcessor] Command VLM failed, falling back to text LLM: \(error.localizedDescription)")
                    let textFallbackSystemPrompt = commandSystemPrompt(
                        options: options,
                        screenContext: screenContext,
                        screenImageAvailable: false,
                        memoryContext: memoryContext,
                        inputContext: inputContext,
                        dictionarySnapshot: dictionarySnapshot
                    )
                    result = try await generateText(
                        prompt: userPrompt,
                        systemPrompt: textFallbackSystemPrompt,
                        options: options,
                        maxTokens: 4096,
                        temperature: 0.3
                    )
                }
            } else {
                result = try await generateText(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    options: options,
                    maxTokens: 4096,
                    temperature: 0.3
                )
            }

            return cleanCommandGeneratedOutput(result, inputLanguage: options.inputLanguage)
        } catch {
            Log.error("[TextProcessor] Command LLM failed: \(error.localizedDescription)")
            return ""
        }
    }

}
