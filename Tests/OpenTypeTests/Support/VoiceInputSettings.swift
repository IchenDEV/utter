import UtterMediaContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
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
