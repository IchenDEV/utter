import AppKit
import Foundation

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

enum VoicePipelineStop: Error {
    case noSpeech
}

@MainActor
extension VoicePipeline {
    func insertFinalText(
        _ output: VoicePipelineOutput,
        raw: String,
        settings: AppSettings,
        expectedEspressoModelPath: String,
        inputMode: VoiceInputMode,
        targetApp: NSRunningApplication?
    ) async {
        let finalText = output.text
        let espressoOutcome = await consumeEspressoOutcome(
            settings: settings,
            expectedEspressoModelPath: expectedEspressoModelPath
        )
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("[VoicePipeline] skipping empty final text")
            showErrorHint(espressoOutcome?.message ?? L("error.operation_failed"))
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
        appState.completionKind = espressoOutcome == .fallback ? .espressoFallback : .standard
        appState.statusMessage = espressoOutcome?.message ?? L("status.done")
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
