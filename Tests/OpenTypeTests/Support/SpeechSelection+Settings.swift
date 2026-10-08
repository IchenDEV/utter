import UtterMediaContracts
import UtterData
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
import UtterModels
import Foundation
import UtterContracts
import UtterPresentationContracts

extension SpeechSelection {
    @MainActor
    init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
        let values = settings.snapshot
        let path = values.speechEngine == .qwen3
            ? ModelCatalog.shared.asrModelPath(for: values.qwenASRModel) : ""
        self.init(settings: values, modelPath: path, inputLanguage: inputLanguage)
    }
}
