import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func processTranslation(
        _ raw: String,
        targetLanguage: TranslationLanguage,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async -> VoicePipelineOutput {
        appState.phase = .processing
        appState.statusMessage = L("pipeline.translating")
        cancelScreenContextCapture()

        let started = CFAbsoluteTimeGetCurrent()
        let inputContext = InputContext.capture(
            targetApp: targetApp,
            screenContext: "",
            outputMode: .processed,
            inputLanguage: settings.inputLanguage,
            source: .menuBar
        )
        let options = TextProcessingOptions(settings: settings)
        let text = await textProcessor.translate(
            text: raw,
            targetLanguage: targetLanguage,
            options: options
        )
        recordFormattingDuration(started, label: "Translation")
        return VoicePipelineOutput(text: text, context: inputContext)
    }
}
