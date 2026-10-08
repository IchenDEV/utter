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
import UtterContracts
import UtterPresentationContracts

extension TextProcessingOptions {
    init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
        self.init(settings: settings.snapshot, inputLanguage: inputLanguage)
    }
}
