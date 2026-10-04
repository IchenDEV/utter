import Foundation

/// Immutable choices for one utterance; settings changes apply to the next session.
package struct VoiceInputSettings {
    package let processing: TextProcessingOptions
    package let speech: SpeechSelection
    package let dictionary: PersonalDictionarySnapshot
    package let outputMode: OutputMode
    package let enableInstantInsert: Bool
    package let allowClipboardPaste: Bool
    package let translationTargetLanguage: TranslationLanguage
    package let enableMemory: Bool
    package let memoryWindowMinutes: Int
    package let useScreenContext: Bool
    package let streamingEnabled: Bool
    package let microphoneID: String?
    package let audioActivityThresholds: AudioActivityThresholds

    package var inputLanguage: InputLanguage { processing.inputLanguage }
    package var llmModel: String { processing.llmModel }
    package var espressoModelPath: String { processing.espressoModelPath }

    package init(settings: SettingsValues, speech: SpeechSelection, dictionary: PersonalDictionarySnapshot,
                 inputLanguage: InputLanguage? = nil) {
        processing = TextProcessingOptions(settings: settings, inputLanguage: inputLanguage)
        self.speech = speech
        self.dictionary = dictionary
        outputMode = settings.outputMode
        enableInstantInsert = settings.enableInstantInsert
        allowClipboardPaste = settings.allowClipboardPaste
        translationTargetLanguage = settings.translationTargetLanguage
        enableMemory = settings.enableMemory
        memoryWindowMinutes = settings.memoryWindowMinutes
        useScreenContext = settings.useScreenContext
        streamingEnabled = settings.enableStreamingRecognitionBeta
        microphoneID = settings.microphoneID
        audioActivityThresholds = settings.audioActivityThresholds
    }
}
