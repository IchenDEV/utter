import Foundation
import UtterContracts
import UtterPresentationContracts

extension VoiceInputSettings {
    @MainActor
    init(settings: AppSettings, inputLanguage: InputLanguage? = nil, bundleIdentifier: String? = nil) {
        self.init(
            settings: settings.snapshot,
            speech: SpeechSelection(settings: settings, inputLanguage: inputLanguage),
            dictionary: PersonalDictionary.shared.snapshot(
                settings: settings, bundleIdentifier: bundleIdentifier,
                languageCode: (inputLanguage ?? settings.inputLanguage).whisperCode
            ), inputLanguage: inputLanguage
        )
    }
}
