import UtterContracts
import UtterModels
import UtterMLX

extension QwenNativeASREngine {
    convenience init(modelPath: String, modelID: String = QwenASRModel.defaultID) {
        self.init(modelPath: modelPath, modelID: modelID, access: LocalModelAccessGate(), log: UtterContracts.Log(service: Log.service))
    }
}

extension MLXSTTEngine {
    convenience init(modelID: String) {
        self.init(modelID: modelID, files: LiveModelFiles(), access: LocalModelAccessGate(), log: UtterContracts.Log(service: Log.service))
    }
}
