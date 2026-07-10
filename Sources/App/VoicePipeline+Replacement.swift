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
        let quickText = immediateInsertText(from: raw, settings: settings)
        let quickContext = InputContext.capture(
            targetApp: targetApp,
            screenContext: "",
            outputMode: .processed,
            inputLanguage: settings.inputLanguage,
            source: .menuBar
        )
        let ocrTask = screenOCRTask
        let ocrStartedAt = screenOCRStartedAt
        screenOCRTask = nil
        screenOCRStartedAt = nil

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

        InputHistory.shared.addRecord(
            rawText: raw,
            processedText: quickText,
            wasProcessed: false,
            context: quickContext
        )
        appState.lastInsertedText = quickText

        let replacement = DeferredReplacement(
            rawText: raw,
            insertedText: quickText,
            targetApp: targetApp,
            message: L("pipeline.background_formatting"),
            context: quickContext
        )
        appState.pendingReplacement = replacement

        replacementTask?.cancel()
        replacementTask = Task { @MainActor [weak self] in
            await self?.finishDeferredSmartFormat(
                replacementID: replacement.id,
                raw: raw,
                settings: settings,
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
        InputHistory.shared.replaceLatestRecord(
            rawText: replacement.rawText,
            processedText: formattedText,
            wasProcessed: true,
            context: replacement.context
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
        settings: AppSettings,
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

        let inputContext = InputContext(
            appName: currentReplacement.targetAppName,
            bundleIdentifier: currentReplacement.targetBundleIdentifier,
            windowTitle: currentReplacement.context?.windowTitle,
            screenContext: screenContext.text,
            outputMode: .processed,
            inputLanguage: settings.inputLanguage,
            source: .menuBar
        )
        let memoryContext = VoicePipelinePolicy.memoryContext(
            for: .processed,
            settings: settings,
            currentContext: inputContext
        )

        let formattedText = await textProcessor.process(
            text: raw,
            stylePrompt: settings.customStylePrompt,
            model: settings.llmModel,
            screenContext: screenContext.text,
            screenImage: screenContext.image,
            memoryContext: memoryContext,
            inputContext: inputContext,
            allowsPreparedFallback: false
        )
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
        replacement.message = L("pipeline.formatted_ready")
        replacement.context = inputContext
        appState.pendingReplacement = replacement
    }

    private func immediateInsertText(from raw: String, settings: AppSettings) -> String {
        let cleaned = textProcessor.prepareForFormatting(text: raw, inputLanguage: settings.inputLanguage)
        let fallback = textProcessor.basicClean(text: raw, inputLanguage: settings.inputLanguage)
        if !cleaned.isEmpty { return cleaned }
        if !fallback.isEmpty { return fallback }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
