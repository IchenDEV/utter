import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterContracts
import UtterModels
import UtterWhisper

extension WhisperEngine {
    convenience init(modelName: String = "large-v3") {
        self.init(modelName: modelName, files: LiveModelFiles(), access: LocalModelAccessGate(), log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
