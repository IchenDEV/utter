import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func handleSpokenEditCommandIfNeeded(
        raw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async -> Bool {
        let expectedEspressoModelPath = settings.espressoModelPath
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
        case .replaceSelection(let replacementRaw):
            await replaceSelectedText(
                raw: raw,
                replacementRaw: replacementRaw,
                settings: settings,
                targetApp: targetApp
            )
        case .rewriteLast(let intent):
            await rewriteLastInsertion(
                raw: raw,
                intent: intent,
                settings: settings,
                targetApp: targetApp
            )
        case .rewriteSelection(let intent):
            await rewriteSelectedText(
                raw: raw,
                intent: intent,
                settings: settings,
                targetApp: targetApp
            )
        case .deleteSelection:
            await deleteSelectedText(targetApp: targetApp)
        case .undoLastInsertion:
            await undoLastInsertion(targetApp: targetApp)
        }

        guard !Task.isCancelled else { return true }
        if let espressoOutcome = await consumeEspressoOutcome(
            settings: settings,
            expectedEspressoModelPath: expectedEspressoModelPath
        ) {
            if case .error = appState.phase, espressoOutcome == .fallback {
                Log.info("[VoicePipeline] preserving edit-command error after Espresso fallback")
            } else if espressoOutcome != .fallback {
                showErrorHint(espressoOutcome.message)
            } else {
                appState.completionKind = .espressoFallback
                appState.statusMessage = espressoOutcome.message
                showOverlay()
                hideOverlayAfterDelay()
            }
        }
        return true
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

        let recordID = InputHistory.shared.addRecord(
            rawText: raw,
            processedText: replacementText,
            wasProcessed: true,
            context: context
        )
        appState.lastInsertedText = replacementText
        beginCorrectionCapture(
            recordID: recordID,
            insertedText: replacementText,
            context: context
        )
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

        let recordID = InputHistory.shared.addRecord(
            rawText: raw,
            processedText: replacementText,
            wasProcessed: true,
            context: context
        )
        appState.lastInsertedText = replacementText
        beginCorrectionCapture(
            recordID: recordID,
            insertedText: replacementText,
            context: context
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

}
