import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func rewriteLastInsertion(
        raw: String,
        intent: SelectionRewriteIntent,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        cancelScreenContextCapture()

        let insertedText = appState.lastInsertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !insertedText.isEmpty else {
            showErrorHint(L("pipeline.no_previous_insert_to_replace"))
            return
        }

        let context = InputContext.capture(
            targetApp: targetApp,
            screenContext: "",
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
            selectedText: insertedText,
            intent: intent,
            options: options,
            spokenCommand: raw,
            memoryContext: memoryContext,
            inputContext: context
        )
        guard !rewrittenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNoSpeechDetected(reason: "last insertion rewrite returned empty text")
            return
        }

        appState.processedText = rewrittenText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.replacing")

        let result = await textInserter.replaceRecentInsertion(
            text: rewrittenText,
            previouslyInserted: appState.lastInsertedText,
            targetApp: targetApp
        )
        InputHistory.shared.addRecord(rawText: raw, processedText: rewrittenText, wasProcessed: true, context: context)

        appState.lastInsertedText = rewrittenText
        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] voice edit last insertion rewrite probably failed: \(reason)")
            TextInserter.copyToClipboard(rewrittenText)
            showInsertionFailedAlert(text: rewrittenText, reason: reason)
        }
    }
}
