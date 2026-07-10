import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func handleSpokenEditCommandIfNeeded(
        raw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async -> Bool {
        guard let command = await resolvedSpokenEditCommand(
            raw: raw,
            settings: settings,
            targetApp: targetApp
        ) else {
            return false
        }

        switch command {
        case .replaceLast(let replacementRaw):
            await replaceLastInsertion(
                raw: raw,
                replacementRaw: replacementRaw,
                settings: settings,
                targetApp: targetApp
            )
            return true
        case .replaceSelection(let replacementRaw):
            await replaceSelectedText(
                raw: raw,
                replacementRaw: replacementRaw,
                settings: settings,
                targetApp: targetApp
            )
            return true
        case .rewriteLast(let intent):
            await rewriteLastInsertion(
                raw: raw,
                intent: intent,
                settings: settings,
                targetApp: targetApp
            )
            return true
        case .rewriteSelection(let intent):
            await rewriteSelectedText(
                raw: raw,
                intent: intent,
                settings: settings,
                targetApp: targetApp
            )
            return true
        case .deleteSelection:
            await deleteSelectedText(targetApp: targetApp)
            return true
        case .undoLastInsertion:
            await undoLastInsertion(targetApp: targetApp)
            return true
        }
    }

    private func replaceLastInsertion(
        raw: String,
        replacementRaw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        cancelScreenContextCapture()

        guard !appState.lastInsertedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showErrorHint(L("pipeline.no_previous_insert_to_replace"))
            return
        }

        let context = replacementInputContext(settings: settings, targetApp: targetApp)
        let replacementText = finalizedReplacementText(replacementRaw, settings: settings)
        guard !replacementText.isEmpty else {
            showNoSpeechDetected(reason: "spoken edit command has empty replacement text")
            return
        }

        appState.processedText = replacementText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.replacing")

        Log.sensitive("[VoicePipeline] voice edit replace \(replacementText.count) chars")
        let result = await textInserter.replaceRecentInsertion(
            text: replacementText,
            previouslyInserted: appState.lastInsertedText,
            targetApp: targetApp
        )

        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] voice edit replacement probably failed: \(reason)")
            TextInserter.copyToClipboard(replacementText)
            showInsertionFailedAlert(text: replacementText, reason: reason)
            return
        }

        InputHistory.shared.addRecord(
            rawText: raw,
            processedText: replacementText,
            wasProcessed: true,
            context: context
        )
        appState.lastInsertedText = replacementText
    }

    private func replaceSelectedText(
        raw: String,
        replacementRaw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        cancelScreenContextCapture()

        let context = replacementInputContext(settings: settings, targetApp: targetApp)
        let replacementText = finalizedReplacementText(replacementRaw, settings: settings)
        guard !replacementText.isEmpty else {
            showNoSpeechDetected(reason: "spoken edit command has empty selection replacement text")
            return
        }

        appState.processedText = replacementText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.replacing")

        Log.sensitive("[VoicePipeline] voice edit replace selection \(replacementText.count) chars")
        let result = await textInserter.replaceSelectedText(text: replacementText, targetApp: targetApp)

        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] voice edit selection replacement probably failed: \(reason)")
            TextInserter.copyToClipboard(replacementText)
            showInsertionFailedAlert(text: replacementText, reason: reason)
            return
        }

        InputHistory.shared.addRecord(
            rawText: raw,
            processedText: replacementText,
            wasProcessed: true,
            context: context
        )
        appState.lastInsertedText = replacementText
    }

    private func replacementInputContext(
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) -> InputContext {
        InputContext.capture(
            targetApp: targetApp,
            screenContext: "",
            outputMode: .command,
            inputLanguage: settings.inputLanguage,
            source: .menuBar
        )
    }

    private func finalizedReplacementText(
        _ text: String,
        settings: AppSettings
    ) -> String {
        textProcessor.cleanCommandGeneratedOutput(
            text,
            inputLanguage: settings.inputLanguage
        )
    }

    private func deleteSelectedText(targetApp: NSRunningApplication?) async {
        cancelScreenContextCapture()

        appState.processedText = ""
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.replacing")

        Log.info("[VoicePipeline] voice edit delete selection")
        let result = await textInserter.deleteSelectedText(targetApp: targetApp)

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] voice edit delete selection probably failed: \(reason)")
            showErrorHint(reason)
            return
        }

        appState.lastInsertedText = ""
        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()
    }

    private func undoLastInsertion(targetApp: NSRunningApplication?) async {
        cancelScreenContextCapture()

        guard !appState.lastInsertedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showErrorHint(L("pipeline.no_previous_insert_to_replace"))
            return
        }

        appState.processedText = ""
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.undoing")

        Log.info("[VoicePipeline] voice edit undo last insertion")
        let result = await textInserter.undoRecentInsertion(
            previouslyInserted: appState.lastInsertedText,
            targetApp: targetApp
        )

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] voice edit undo probably failed: \(reason)")
            showErrorHint(reason)
            return
        }

        appState.lastInsertedText = ""
        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()
    }

    private func rewriteSelectedText(
        raw: String,
        intent: SelectionRewriteIntent,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        cancelScreenContextCapture()

        guard let selectedText = await textInserter.selectedText(targetApp: targetApp),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showErrorHint(L("pipeline.no_selected_text_to_replace"))
            return
        }

        let context = InputContext.capture(
            targetApp: targetApp,
            screenContext: "",
            selectedTextOverride: selectedText,
            outputMode: .command,
            inputLanguage: settings.inputLanguage,
            source: .menuBar
        )
        var options = TextProcessingOptions(settings: settings)
        options.llmModel = settings.llmModel
        let memoryContext = VoicePipelinePolicy.memoryContext(
            for: .command,
            settings: settings,
            currentContext: context
        )

        appState.phase = .processing
        appState.statusMessage = L("pipeline.formatting")
        let rewrittenText = await textProcessor.processSelectionEdit(
            selectedText: selectedText,
            intent: intent,
            options: options,
            spokenCommand: raw,
            memoryContext: memoryContext,
            inputContext: context
        )
        guard !rewrittenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNoSpeechDetected(reason: "selection rewrite returned empty text")
            return
        }

        appState.processedText = rewrittenText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.replacing")

        let result = await textInserter.replaceSelectedText(text: rewrittenText, targetApp: targetApp)
        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] voice edit selection rewrite probably failed: \(reason)")
            TextInserter.copyToClipboard(rewrittenText)
            showInsertionFailedAlert(text: rewrittenText, reason: reason)
            return
        }

        InputHistory.shared.addRecord(
            rawText: raw,
            processedText: rewrittenText,
            wasProcessed: true,
            context: context
        )
        appState.lastInsertedText = rewrittenText
    }
}
