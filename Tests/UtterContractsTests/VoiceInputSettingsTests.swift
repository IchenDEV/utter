import XCTest
@testable import UtterContracts

final class VoiceInputSettingsTests: XCTestCase {
    func testOneUtteranceRetainsItsProviderCredentialsLanguageAndDictionary() {
        var preferences = SettingsValues()
        preferences.remoteAPIKey = "admitted-secret"
        preferences.inputLanguage = .english
        preferences.llmModel = "admitted-model"
        preferences.microphoneID = "admitted-microphone"
        let speech = SpeechSelection(providerID: "replacement.speech", type: .whisper, model: "replacement-model")
        let dictionary = PersonalDictionarySnapshot(entries: [DictionaryEntry(original: "helo", replacement: "hello")], editRules: [])
        let snapshot = VoiceInputSettings(settings: preferences, speech: speech, dictionary: dictionary)
        preferences.remoteAPIKey = "later-secret"
        preferences.inputLanguage = .chinese
        preferences.llmModel = "later-model"
        preferences.microphoneID = "later-microphone"
        XCTAssertEqual(snapshot.processing.remoteAPIKey, "admitted-secret")
        XCTAssertEqual(snapshot.inputLanguage, .english)
        XCTAssertEqual(snapshot.llmModel, "admitted-model")
        XCTAssertEqual(snapshot.microphoneID, "admitted-microphone")
        XCTAssertEqual(snapshot.speech.providerID, "replacement.speech")
        XCTAssertEqual(snapshot.speech.model, "replacement-model")
        XCTAssertEqual(snapshot.dictionary.applyReplacements(to: "helo"), "hello")
    }
}
