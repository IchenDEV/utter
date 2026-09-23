import Foundation

/// Immutable choices for one utterance; settings changes apply to the next session.
struct VoiceInputSettings {
    let processing: TextProcessingOptions
    let speech: SpeechEngineProvider.Selection
    let dictionary: PersonalDictionarySnapshot
    let outputMode: OutputMode
    let enableInstantInsert: Bool
    let enableMemory: Bool
    let memoryWindowMinutes: Int
    let useScreenContext: Bool
    let streamingEnabled: Bool
    let microphoneID: String?
    let audioActivityThresholds: AudioActivityThresholds

    var inputLanguage: InputLanguage { processing.inputLanguage }
    var llmModel: String { processing.llmModel }
    var espressoModelPath: String { processing.espressoModelPath }

    @MainActor
    init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
        processing = TextProcessingOptions(settings: settings, inputLanguage: inputLanguage)
        speech = SpeechEngineProvider.Selection(settings: settings, inputLanguage: inputLanguage)
        dictionary = PersonalDictionary.shared.snapshot(settings: settings)
        outputMode = settings.outputMode
        enableInstantInsert = settings.enableInstantInsert
        enableMemory = settings.enableMemory
        memoryWindowMinutes = settings.memoryWindowMinutes
        useScreenContext = settings.useScreenContext
        streamingEnabled = settings.enableStreamingRecognitionBeta
        microphoneID = settings.microphoneID
        audioActivityThresholds = settings.audioActivityThresholds
    }
}
