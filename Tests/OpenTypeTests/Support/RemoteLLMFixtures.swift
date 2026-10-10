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

extension RemoteLLMClient {
    init() {
        self.init(transport: URLSessionRemoteTransport(), log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
