import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func refreshPendingReplacement() {
        guard var replacement = appState.pendingReplacement else { return }
        guard replacement.state == .ready, Date() >= replacement.expiresAt else { return }
        replacement.state = .expired
        replacement.message = L("pipeline.replacement_expired")
        appState.pendingReplacement = replacement
    }

    func applyPendingReplacement() async {
        refreshPendingReplacement()

        guard var replacement = appState.pendingReplacement else { return }
        let decision = DeferredReplacementPolicy.decision(
            for: replacement,
            currentBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )

        switch decision {
        case .replace:
            await replacePendingText(replacement)
        case .copy(let reason):
            guard reason != .notReady else {
                replacement.message = L("pipeline.replacement_not_ready")
                appState.pendingReplacement = replacement
                return
            }
            copyPendingReplacement(&replacement, reason: reason)
        }
    }

    func handleDeferredSmartFormat(
        raw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        let processingOptions = TextProcessingOptions(settings: settings)
        let dictionarySnapshot = PersonalDictionary.shared.snapshot(settings: settings)
        let enableMemory = settings.enableMemory
        let memoryWindowMinutes = settings.memoryWindowMinutes
        let quickText = immediateInsertText(
            from: raw,
            inputLanguage: processingOptions.inputLanguage,
            dictionarySnapshot: dictionarySnapshot
        )
        let quickContext = InputContext.capture(
            targetApp: targetApp,
            screenContext: "",
            outputMode: .processed,
            inputLanguage: processingOptions.inputLanguage,
            source: .menuBar
        )
        let formatDecision = TextFormatClassifier.classify(text: raw, context: quickContext)
        let ocrTask = screenOCRTask
        let ocrStartedAt = screenOCRStartedAt
        screenOCRTask = nil
        screenOCRStartedAt = nil

        guard !quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ocrTask?.cancel()
            showNoSpeechDetected(
                reason: "instant-insert preprocessing produced empty text"
            )
            return
        }

        appState.processedText = quickText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.inserting")

        Log.sensitive("[VoicePipeline] instant insert \(quickText.count) chars")
        let started = CFAbsoluteTimeGetCurrent()
        let result = await textInserter.insert(text: quickText, targetApp: targetApp)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[VoicePipeline] instant insert stage finished in \(String(format: "%.2f", elapsed))s")

        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] instant insertion probably failed: \(reason)")
            TextInserter.copyToClipboard(quickText)
            showInsertionFailedAlert(text: quickText, reason: reason)
            return
        }

        let recordID = InputHistory.shared.addRecord(
            rawText: raw,
            processedText: quickText,
            wasProcessed: false,
            context: quickContext,
            formatKind: formatDecision.kind
        )
        appState.lastInsertedText = quickText
        beginCorrectionCapture(
            recordID: recordID,
            insertedText: quickText,
            context: quickContext
        )

        let replacement = DeferredReplacement(
            rawText: raw,
            insertedText: quickText,
            targetApp: targetApp,
            message: L("pipeline.background_formatting"),
            context: quickContext,
            formatKind: formatDecision.kind
        )
        appState.pendingReplacement = replacement

        replacementTask?.cancel()
        replacementTask = Task { @MainActor [weak self] in
            await self?.finishDeferredSmartFormat(
                replacementID: replacement.id,
                raw: raw,
                processingOptions: processingOptions,
                dictionarySnapshot: dictionarySnapshot,
                enableMemory: enableMemory,
                memoryWindowMinutes: memoryWindowMinutes,
                ocrTask: ocrTask,
                ocrStartedAt: ocrStartedAt
            )
        }
    }

    private func replacePendingText(_ replacement: DeferredReplacement) async {
        guard let formattedText = replacement.formattedText else { return }
        guard let targetApp = replacement.targetApplication else {
            var copied = replacement
            copyPendingReplacement(&copied, reason: .missingTarget)
            return
        }

        appState.phase = .inserting
        appState.statusMessage = L("pipeline.replacing")

        correctionCapture.finishCurrentSession()

        let result = await textInserter.replaceRecentInsertion(
            text: formattedText,
            previouslyInserted: replacement.insertedText,
            targetApp: targetApp
        )

        if case .probablyFailed = result {
            TextInserter.copyToClipboard(formattedText)
            var copied = replacement
            copied.state = .copied
            copied.message = L("pipeline.replacement_copied_failed")
            appState.pendingReplacement = copied
            appState.phase = .done
            appState.statusMessage = L("status.done")
            return
        }

        appState.processedText = formattedText
        appState.lastInsertedText = formattedText
        let recordID = InputHistory.shared.replaceLatestRecord(
            rawText: replacement.rawText,
            processedText: formattedText,
            wasProcessed: true,
            context: replacement.context,
            formatKind: replacement.formatKind
        )
        beginCorrectionCapture(
            recordID: recordID,
            insertedText: formattedText,
            context: replacement.context ?? InputContext(
                appName: replacement.targetAppName,
                bundleIdentifier: replacement.targetBundleIdentifier,
                outputMode: .processed,
                inputLanguage: appState.settings.inputLanguage,
                source: .menuBar
            )
        )
        appState.clearPendingReplacement()
        appState.phase = .done
        appState.statusMessage = L("status.done")
    }

    private func copyPendingReplacement(_ replacement: inout DeferredReplacement, reason: DeferredReplacementCopyReason) {
        guard let formattedText = replacement.formattedText else { return }
        TextInserter.copyToClipboard(formattedText)
        replacement.state = .copied
        replacement.message = replacementCopyMessage(for: reason)
        appState.pendingReplacement = replacement
    }

    private func finishDeferredSmartFormat(
        replacementID: UUID,
        raw: String,
        processingOptions: TextProcessingOptions,
        dictionarySnapshot: PersonalDictionarySnapshot,
        enableMemory: Bool,
        memoryWindowMinutes: Int,
        ocrTask: Task<ScreenContextSnapshot, Never>?,
        ocrStartedAt: CFAbsoluteTime?
    ) async {
        let started = CFAbsoluteTimeGetCurrent()
        let screenContext = await ocrTask?.value ?? .empty
        if let ocrStartedAt {
            let elapsed = CFAbsoluteTimeGetCurrent() - ocrStartedAt
            Log.info("[VoicePipeline] screen context stage finished in \(String(format: "%.2f", elapsed))s")
        }

        guard !Task.isCancelled else { return }
        guard let currentReplacement = appState.pendingReplacement, currentReplacement.id == replacementID else { return }

        let inputContext = Self.deferredInputContext(
            for: currentReplacement,
            screenContext: screenContext.text,
            inputLanguage: processingOptions.inputLanguage
        )
        let memoryContext = VoicePipelinePolicy.memoryContext(
            for: .processed,
            enableMemory: enableMemory,
            memoryWindowMinutes: memoryWindowMinutes,
            currentContext: inputContext
        )

        let formattedText = await textProcessor.process(
            text: raw,
            options: processingOptions,
            screenContext: screenContext.text,
            screenImage: screenContext.image,
            memoryContext: memoryContext,
            inputContext: inputContext,
            formatKind: currentReplacement.formatKind,
            allowsPreparedFallback: false,
            allowsGuardFallback: false,
            dictionarySnapshot: dictionarySnapshot
        )
        let fallbackMessage = await applyEspressoFallbackIfNeeded(settings: appState.settings)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        appState.lastFormattingDurationSeconds = elapsed
        Log.info("[VoicePipeline] Smart Format completed in \(String(format: "%.2f", elapsed))s")

        guard !Task.isCancelled else { return }
        guard var replacement = appState.pendingReplacement, replacement.id == replacementID else { return }

        guard !formattedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("[VoicePipeline] deferred Smart Format produced no LLM output")
            replacement.state = .failed
            replacement.message = L("pipeline.formatting_failed")
            replacement.context = inputContext
            appState.pendingReplacement = replacement
            return
        }

        replacement.formattedText = formattedText
        replacement.state = .ready
        replacement.message = fallbackMessage ?? L("pipeline.formatted_ready")
        replacement.context = inputContext
        appState.pendingReplacement = replacement
    }

    static func deferredInputContext(
        for replacement: DeferredReplacement,
        screenContext: String,
        inputLanguage: InputLanguage
    ) -> InputContext {
        InputContext(
            appName: replacement.targetAppName,
            bundleIdentifier: replacement.targetBundleIdentifier,
            windowTitle: replacement.context?.windowTitle,
            screenContext: screenContext,
            textBeforeSelection: replacement.context?.textBeforeSelection,
            selectedText: replacement.context?.selectedText,
            textAfterSelection: replacement.context?.textAfterSelection,
            outputMode: .processed,
            inputLanguage: inputLanguage,
            source: .menuBar
        )
    }

    private func immediateInsertText(
        from raw: String,
        inputLanguage: InputLanguage,
        dictionarySnapshot: PersonalDictionarySnapshot
    ) -> String {
        let cleaned = textProcessor.prepareForFormatting(
            text: raw,
            inputLanguage: inputLanguage,
            dictionarySnapshot: dictionarySnapshot
        )
        let fallback = textProcessor.basicClean(
            text: raw,
            inputLanguage: inputLanguage,
            dictionarySnapshot: dictionarySnapshot
        )
        if !cleaned.isEmpty { return cleaned }
        if !fallback.isEmpty { return fallback }
        return ""
    }

    private func replacementCopyMessage(for reason: DeferredReplacementCopyReason) -> String {
        switch reason {
        case .expired:
            return L("pipeline.replacement_copied_expired")
        case .missingTarget:
            return L("pipeline.replacement_copied_missing_target")
        case .appChanged:
            return L("pipeline.replacement_copied_app_changed")
        case .notReady:
            return L("pipeline.replacement_not_ready")
        }
    }
}
