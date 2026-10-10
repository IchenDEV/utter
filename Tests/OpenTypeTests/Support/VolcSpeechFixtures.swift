import UtterMediaContracts
import UtterPresentationContracts
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
import UtterIngress
import UtterContracts
import UtterRemoteInference

extension VolcSpeechEngine {
    convenience init(appKey: String, accessKey: String, resourceId: String) {
        self.init(appKey: appKey, accessKey: accessKey, resourceId: resourceId, log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
