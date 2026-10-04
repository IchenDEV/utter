import UtterContracts
import UtterRuntime

@MainActor
package enum ProcessingPlugins {
    package static func preparation() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "processing.preparation", provides: [ProcessingServices.preparation.reference])) { context, _ in
            try context.provide(ProcessingServices.preparation, value: BuiltinTextPreparation())
        }
    }
}

private struct BuiltinTextPreparation: TextPreparationService {
    func transcript(_ text: String, activity: AudioCaptureActivity?, recognitionPhrases: [String]) -> String? {
        TranscriptionSanitizer.prepare(text, audioActivity: activity, recognitionPhrases: recognitionPhrases)
    }
    func preview(_ text: String, language: InputLanguage) -> String {
        TranscriptionSanitizer.previewText(text, inputLanguage: language)
    }
    func format(text: String, context: InputContext?) -> TextFormatDecision {
        TextFormatClassifier.classify(text: text, context: context)
    }
}
