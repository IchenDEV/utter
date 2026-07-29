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
    func warmUpLLM(
        model: String,
        estimatedDownloadBytes: Int64? = nil,
        progress: (@Sendable (DownloadProgressInfo) -> Void)? = nil
    ) async -> Bool {
        if AppSettings.shared.useRemoteLLM { return true }
        do {
            try await llm.loadModel(
                id: model,
                estimatedDownloadBytes: estimatedDownloadBytes,
                progress: progress
            )
            return true
        } catch {
            Log.error("[TextProcessor] LLM warmup failed: \(error.localizedDescription)")
            return false
        }
    }

    func basicClean(text: String, inputLanguage: InputLanguage = .auto) -> String {
        var result = dictionary.applyReplacements(to: text)
        result = normalizeWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prepareForFormatting(text: String, inputLanguage: InputLanguage) -> String {
        var result = dictionary.applyReplacements(to: text)
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
        allowsPreparedFallback: Bool = TextProcessor.defaultAllowsPreparedFallback
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
            allowsPreparedFallback: allowsPreparedFallback
        )
    }

    func process(
        text: String,
        options: TextProcessingOptions,
        screenContext: String = "",
        screenImage: CGImage? = nil,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        allowsPreparedFallback: Bool = TextProcessor.defaultAllowsPreparedFallback
    ) async -> String {
        let prepareStarted = CFAbsoluteTimeGetCurrent()
        let cleanedText = prepareForFormatting(text: text, inputLanguage: options.inputLanguage)
        let prepareElapsed = CFAbsoluteTimeGetCurrent() - prepareStarted
        Log.info("[TextProcessor] prepared LLM input \(text.count) chars to \(cleanedText.count) chars in \(String(format: "%.2f", prepareElapsed))s")
        guard !cleanedText.isEmpty else { return "" }

        let systemPrompt = systemPromptWithPersonalContext(
            PromptBuilder.buildSystemPrompt(
                style: options.languageStyle,
                stylePrompt: options.customStylePrompt,
                screenContext: screenContext,
                screenImageAvailable: shouldUseScreenImage(options: options, image: screenImage),
                memoryContext: memoryContext,
                inputContext: inputContext,
                inputLanguage: options.inputLanguage
            ),
            inputLanguage: options.inputLanguage
        )

        let userPrompt = PromptBuilder.buildUserPrompt(text: cleanedText, inputLanguage: options.inputLanguage)
        let generationOptions = formattingOptions(for: cleanedText, style: options.languageStyle)

        do {
            var result: String
            let llmStarted = CFAbsoluteTimeGetCurrent()
            if let screenImage, shouldUseScreenImage(options: options, image: screenImage) {
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
                    result = try await generateText(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
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
            return cleanGeneratedOutput(result, inputLanguage: options.inputLanguage, fallback: fallback)
        } catch {
            if allowsPreparedFallback {
                Log.error("[TextProcessor] LLM failed, falling back to prepared raw text: \(error.localizedDescription)")
                return FormattedOutputCleaner.clean(cleanedText)
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
        inputContext: InputContext? = nil
    ) async -> String {
        let systemPrompt = systemPromptWithPersonalContext(
            PromptBuilder.buildCommandSystemPrompt(
                screenContext: screenContext,
                screenImageAvailable: shouldUseScreenImage(options: options, image: screenImage),
                memoryContext: memoryContext,
                inputContext: inputContext,
                inputLanguage: options.inputLanguage
            ),
            inputLanguage: options.inputLanguage
        )
        let userPrompt = PromptBuilder.buildCommandUserPrompt(
            text: text,
            inputLanguage: options.inputLanguage
        )

        do {
            var result: String
            if let screenImage, shouldUseScreenImage(options: options, image: screenImage) {
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
                    result = try await generateText(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
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

    /// Dictionary replacements are applied once on the input side
    /// (`prepareForFormatting` / `basicClean`); reapplying them here could
    /// double-expand terms whose replacement contains the original.
    func cleanGeneratedOutput(_ text: String, inputLanguage: InputLanguage, fallback: String = "") -> String {
        var result = stripThinkingTags(text)
        result = FormattedOutputCleaner.clean(result)
        if result.isEmpty { return FormattedOutputCleaner.clean(fallback) }
        return result
    }

    /// Command prompts advertise a final_text JSON contract, so honoring that
    /// envelope here is contract parsing, not guessing. The command output is
    /// entirely model-generated — no dictated content can be swallowed.
    func cleanCommandGeneratedOutput(_ text: String, inputLanguage: InputLanguage) -> String {
        let stripped = stripThinkingTags(text)
        if let finalText = LLMFinalTextOutput.text(from: stripped) {
            return FormattedOutputCleaner.clean(finalText)
        }
        return cleanGeneratedOutput(text, inputLanguage: inputLanguage)
    }

    func systemPromptWithPersonalContext(_ systemPrompt: String, inputLanguage: InputLanguage) -> String {
        let extraSections = [
            PromptCatalog.activePersonalDictionarySection(
                dictionary.activeEntriesDescription(),
                inputLanguage: inputLanguage
            ),
            PromptCatalog.activeEditRulesSection(
                dictionary.activeRulesDescription(),
                inputLanguage: inputLanguage
            ),
        ].compactMap { $0 }

        guard !extraSections.isEmpty else { return systemPrompt }
        return ([systemPrompt] + extraSections).joined(separator: "\n\n")
    }

    /// Collapses runs of spaces but keeps line breaks: direct mode promises
    /// verbatim output, and ASR engines only emit newlines deliberately.
    private func normalizeWhitespace(_ text: String) -> String {
        TranscriptionSanitizer.normalizeInput(text)
            .replacingOccurrences(of: "[^\\S\\n]*\\n[^\\S\\n]*", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[^\\S\\n]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    }
}
