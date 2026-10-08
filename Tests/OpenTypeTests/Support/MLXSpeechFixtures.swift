import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterContracts
import UtterModels
import UtterMLX

extension QwenNativeASREngine {
    convenience init(modelPath: String, modelID: String = QwenASRModel.defaultID) {
        self.init(modelPath: modelPath, modelID: modelID, access: LocalModelAccessGate(), log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}

extension MLXSTTEngine {
    convenience init(modelID: String) {
        self.init(modelID: modelID, files: LiveModelFiles(), access: LocalModelAccessGate(), log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
