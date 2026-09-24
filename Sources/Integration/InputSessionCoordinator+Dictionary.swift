import Foundation

@MainActor
extension InputSessionCoordinator {
    func recognitionContext(
        engine: any SpeechEngine,
        snapshot: PersonalDictionarySnapshot
    ) -> SpeechRecognitionContext {
        return SpeechRecognitionContext(phrases: engine is QwenNativeASREngine
            ? snapshot.personalRecognitionPhrases
            : snapshot.recognitionPhrases)
    }

    func recordingContainsSpeech(_ audioURL: URL?) async -> Bool {
        #if DEBUG
        if let speechActivityOverrideForTesting {
            return await speechActivityOverrideForTesting(audioURL)
        }
        #endif
        return await SpeechActivityClassifier.containsSpeech(at: audioURL)
    }
}
