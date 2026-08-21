import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func confirmPendingMedicalDraft() async {
        guard let draft = appState.pendingMedicalDraft else { return }
        appState.pendingMedicalDraft = nil
        await commitFinalText(
            draft.text,
            raw: draft.rawText,
            context: draft.context,
            formatKind: draft.formatKind,
            targetApp: draft.targetApplication,
            wasProcessed: draft.wasProcessed,
            allowsCorrectionCapture: draft.allowsCorrectionCapture
        )
    }

    func discardPendingMedicalDraft() {
        appState.pendingMedicalDraft = nil
        appState.processedText = ""
        appState.phase = .idle
        appState.statusMessage = L("medical_draft.discarded")
    }

    func commitFinalText(
        _ finalText: String,
        raw: String,
        context: InputContext,
        formatKind: TextFormatKind?,
        targetApp: NSRunningApplication?,
        wasProcessed: Bool,
        allowsCorrectionCapture: Bool
    ) async {
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

        appState.lastInsertedText = finalText
        if ProductEdition.current.capabilities.activityHistory {
            let recordID = InputHistory.shared.addRecord(
                rawText: raw,
                processedText: finalText,
                wasProcessed: wasProcessed,
                context: context,
                formatKind: formatKind
            )
            if allowsCorrectionCapture,
               ProductEdition.current.capabilities.correctionLearning {
                beginCorrectionCapture(
                    recordID: recordID,
                    insertedText: finalText,
                    context: context
                )
            }
        } else if allowsCorrectionCapture,
                  ProductEdition.current.capabilities.correctionLearning {
            // Correction learning requires a history record to compare against.
            Log.info("[VoicePipeline] correction capture skipped because history is disabled")
        }
    }
}
