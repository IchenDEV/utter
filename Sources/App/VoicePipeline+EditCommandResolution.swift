import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func resolvedSpokenEditCommand(
        raw: String,
        settings: VoiceInputSettings,
        targetApp: NSRunningApplication?
    ) async -> SpokenEditCommand? {
        guard VoicePipelinePolicy.shouldResolveEditCommandWithLLMFirst(outputMode: settings.outputMode) else {
            return nil
        }

        let resolution = await resolveSpokenEditCommandWithLLM(
            raw: raw,
            settings: settings,
            targetApp: targetApp
        )
        return VoicePipelinePolicy.editCommand(from: resolution)
    }

    func spokenEditCommandResolutionContext(
        targetApp: NSRunningApplication?
    ) async -> SpokenEditCommandResolutionContext {
        let lastInsertedText = appState.lastInsertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastInsertion = lastInsertedText.isEmpty
            ? SpokenEditCommandTargetAvailability.unavailable
            : .available
        let selectedText = await textInserter.selectedText(targetApp: targetApp)
        let selectionAvailability: SpokenEditCommandTargetAvailability
        if let selectedText {
            selectionAvailability = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .unavailable
                : .available
        } else {
            selectionAvailability = .unknown
        }

        return SpokenEditCommandResolutionContext(
            lastInsertion: lastInsertion,
            selectedText: selectionAvailability,
            lastInsertionPreview: SpokenEditCommandResolutionContext.preview(lastInsertedText),
            selectedTextPreview: SpokenEditCommandResolutionContext.preview(selectedText)
        )
    }

    private func resolveSpokenEditCommandWithLLM(
        raw: String,
        settings: VoiceInputSettings,
        targetApp: NSRunningApplication?
    ) async -> SpokenEditCommandLLMResolution? {
        var options = settings.processing
        options.llmModel = settings.llmModel
        return await textProcessor.resolveSpokenEditCommandResolution(
            text: raw,
            options: options,
            context: await spokenEditCommandResolutionContext(targetApp: targetApp)
        )
    }
}
