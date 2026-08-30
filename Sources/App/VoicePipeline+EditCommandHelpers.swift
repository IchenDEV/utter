import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func replacementInputContext(
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

    func finalizedReplacementText(
        _ text: String,
        settings: AppSettings
    ) -> String {
        textProcessor.cleanCommandGeneratedOutput(
            text,
            inputLanguage: settings.inputLanguage
        )
    }

    func rewriteSelectedText(
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

        let recordID = InputHistory.shared.addRecord(
            rawText: raw,
            processedText: rewrittenText,
            wasProcessed: true,
            context: context
        )
        appState.lastInsertedText = rewrittenText
        beginCorrectionCapture(
            recordID: recordID,
            insertedText: rewrittenText,
            context: context
        )
    }
}
