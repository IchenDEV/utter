import Foundation

@MainActor
extension InputSessionCoordinator {
    func dictionarySnapshot(clientID: String, languageCode: String?) -> PersonalDictionarySnapshot {
        PersonalDictionary.shared.snapshot(
            settings: settings,
            bundleIdentifier: service.integrationClient(id: clientID)?.bundleIdentifier,
            languageCode: languageCode
        )
    }

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
