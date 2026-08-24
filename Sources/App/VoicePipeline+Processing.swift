import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func processRecording(
        audioURL: URL?,
        audioActivity: AudioCaptureActivity,
        language: String?,
        settings: AppSettings,
        inputMode: VoiceInputMode,
        targetApp: NSRunningApplication?
    ) async {
        defer { audioCapture.cleanupLastRecording() }

        do {
            guard audioActivity.hasMeaningfulAudio else {
                showNoSpeechDetected(reason: "recorded audio energy below threshold")
                return
            }

            let preparedRaw = try await transcribePreparedText(
                audioURL: audioURL,
                audioActivity: audioActivity,
                language: language,
                settings: settings
            )

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

            if !inputMode.isTranslation {
                if await handleSpokenEditCommandIfNeeded(
                    raw: preparedRaw,
                    settings: settings,
                    targetApp: targetApp
                ) {
                    return
                }

                if DeferredReplacementPolicy.shouldUseDeferredReplacement(
                    outputMode: settings.outputMode,
                    enableInstantInsert: settings.enableInstantInsert
                ) {
                    await handleDeferredSmartFormat(raw: preparedRaw, settings: settings, targetApp: targetApp)
                    return
                }
            }

            let output = await outputText(
                for: preparedRaw,
                settings: settings,
                inputMode: inputMode,
                targetApp: targetApp
            )

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

            await insertFinalText(
                output,
                raw: preparedRaw,
                settings: settings,
                inputMode: inputMode,
                targetApp: targetApp
            )
        } catch VoicePipelineStop.noSpeech {
            return
        } catch {
            currentEngine?.cancelListening()
            if Task.isCancelled {
                resetToIdle()
                return
            }
            let message = userFacingErrorMessage(for: error)
            Log.error("[VoicePipeline] error: \(error.localizedDescription)")
            appState.phase = .error(message)
            appState.statusMessage = L("pipeline.error_prefix") + message
            hideOverlayAfterDelay()
        }
    }

    private func transcribePreparedText(
        audioURL: URL?,
        audioActivity: AudioCaptureActivity,
        language: String?,
        settings: AppSettings
    ) async throws -> String {
        let started = CFAbsoluteTimeGetCurrent()
        let raw: String
        if settings.enableStreamingRecognitionBeta {
            raw = try await currentEngine?.finishListening(audioURL: audioURL, language: language) ?? ""
        } else {
            raw = try await currentEngine?.transcribe(audioURL: audioURL, language: language) ?? ""
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[VoicePipeline] ASR stage finished in \(String(format: "%.2f", elapsed))s")

        guard let prepared = TranscriptionSanitizer.prepare(raw, audioActivity: audioActivity) else {
            showNoSpeechDetected(reason: "transcription has no meaningful content: \(raw)")
            throw VoicePipelineStop.noSpeech
        }

        appState.rawTranscription = prepared
        return prepared
    }

    private func outputText(
        for raw: String,
        settings: AppSettings,
        inputMode: VoiceInputMode,
        targetApp: NSRunningApplication?
    ) async -> VoicePipelineOutput {
        if case .translation(let targetLanguage) = inputMode {
            return await processTranslation(
                raw,
                targetLanguage: targetLanguage,
                settings: settings,
                targetApp: targetApp
            )
        }

        switch settings.outputMode {
        case .processed:
            return await processSmartFormat(raw, settings: settings, targetApp: targetApp)
        case .command:
            return await processCommand(raw, settings: settings, targetApp: targetApp)
        case .direct:
            cancelScreenContextCapture()
            let dictionarySnapshot = PersonalDictionary.shared.snapshot(settings: settings)
            let context = InputContext.capture(
                targetApp: targetApp,
                screenContext: "",
                outputMode: .direct,
                inputLanguage: settings.inputLanguage,
                source: .menuBar
            )
            return VoicePipelineOutput(
                text: textProcessor.basicClean(
                    text: raw,
                    inputLanguage: settings.inputLanguage,
                    dictionarySnapshot: dictionarySnapshot
                ),
                context: context
            )
        }
    }

    private func processSmartFormat(
        _ raw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async -> VoicePipelineOutput {
        appState.phase = .processing
        appState.statusMessage = L("pipeline.formatting")

        let started = CFAbsoluteTimeGetCurrent()
        let processingOptions = TextProcessingOptions(settings: settings)
        let dictionarySnapshot = PersonalDictionary.shared.snapshot(settings: settings)
        let enableMemory = settings.enableMemory
        let memoryWindowMinutes = settings.memoryWindowMinutes
        let screenContext = await finishScreenContextCapture()
        let inputContext = InputContext.capture(
            targetApp: targetApp,
            screenContext: screenContext.text,
            outputMode: .processed,
            inputLanguage: processingOptions.inputLanguage,
            source: .menuBar
        )
        guard !Task.isCancelled else { return VoicePipelineOutput(text: "", context: inputContext) }

        let memoryContext = VoicePipelinePolicy.memoryContext(
            for: .processed,
            enableMemory: enableMemory,
            memoryWindowMinutes: memoryWindowMinutes,
            currentContext: inputContext
        )
        let formatDecision = TextFormatClassifier.classify(text: raw, context: inputContext)
        Log.info("[VoicePipeline] format kind \(formatDecision.kind.rawValue) (\(formatDecision.reason.rawValue))")
        let text = await textProcessor.process(
            text: raw,
            options: processingOptions,
            screenContext: screenContext.text,
            screenImage: screenContext.image,
            memoryContext: memoryContext,
            inputContext: inputContext,
            formatKind: formatDecision.kind,
            dictionarySnapshot: dictionarySnapshot
        )
        recordFormattingDuration(started, label: "Smart Format")
        return VoicePipelineOutput(text: text, context: inputContext, formatKind: formatDecision.kind)
    }

    private func processCommand(
        _ raw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async -> VoicePipelineOutput {
        appState.phase = .processing
        appState.statusMessage = L("pipeline.formatting")

        let started = CFAbsoluteTimeGetCurrent()
        let processingOptions = TextProcessingOptions(settings: settings)
        let dictionarySnapshot = PersonalDictionary.shared.snapshot(settings: settings)
        let enableMemory = settings.enableMemory
        let memoryWindowMinutes = settings.memoryWindowMinutes
        let screenContext = await finishScreenContextCapture()
        let inputContext = InputContext.capture(
            targetApp: targetApp,
            screenContext: screenContext.text,
            outputMode: .command,
            inputLanguage: processingOptions.inputLanguage,
            source: .menuBar
        )
        guard !Task.isCancelled else { return VoicePipelineOutput(text: "", context: inputContext) }

        let memoryContext = VoicePipelinePolicy.memoryContext(
            for: .command,
            enableMemory: enableMemory,
            memoryWindowMinutes: memoryWindowMinutes,
            currentContext: inputContext
        )
        let text = await textProcessor.processCommand(
            text: raw,
            options: processingOptions,
            screenContext: screenContext.text,
            screenImage: screenContext.image,
            memoryContext: memoryContext,
            inputContext: inputContext,
            dictionarySnapshot: dictionarySnapshot
        )
        recordFormattingDuration(started, label: "Voice Command formatting")
        return VoicePipelineOutput(text: text, context: inputContext)
    }

    func recordFormattingDuration(_ started: CFAbsoluteTime, label: String) {
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        appState.lastFormattingDurationSeconds = elapsed
        Log.info("[VoicePipeline] \(label) completed in \(String(format: "%.2f", elapsed))s")
    }

    private func insertFinalText(
        _ output: VoicePipelineOutput,
        raw: String,
        settings: AppSettings,
        inputMode: VoiceInputMode,
        targetApp: NSRunningApplication?
    ) async {
        let finalText = output.text
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("[VoicePipeline] skipping empty final text")
            showErrorHint(L("error.operation_failed"))
            return
        }

        appState.processedText = finalText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.inserting")

        Log.sensitive("[VoicePipeline] inserting \(finalText.count) chars")
        let started = CFAbsoluteTimeGetCurrent()
        let result = await textInserter.insert(text: finalText, targetApp: targetApp)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[VoicePipeline] insert stage finished in \(String(format: "%.2f", elapsed))s")

        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] insertion probably failed: \(reason)")
            TextInserter.copyToClipboard(finalText)
            showInsertionFailedAlert(text: finalText, reason: reason)
            return
        }

        let wasProcessed = inputMode.isTranslation
            || settings.outputMode == .processed
            || settings.outputMode == .command
        let recordID = InputHistory.shared.addRecord(
            rawText: raw,
            processedText: finalText,
            wasProcessed: wasProcessed,
            context: output.context,
            formatKind: output.formatKind
        )
        appState.lastInsertedText = finalText
        if !inputMode.isTranslation {
            beginCorrectionCapture(
                recordID: recordID,
                insertedText: finalText,
                context: output.context
            )
        }
    }
}

struct VoicePipelineOutput {
    let text: String
    let context: InputContext
    let formatKind: TextFormatKind?

    init(text: String, context: InputContext, formatKind: TextFormatKind? = nil) {
        self.text = text
        self.context = context
        self.formatKind = formatKind
    }
}

private enum VoicePipelineStop: Error {
    case noSpeech
}
