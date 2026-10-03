import UtterContracts
import UtterModels
import UtterWhisper

extension WhisperEngine {
    convenience init(modelName: String = "large-v3") {
        self.init(modelName: modelName, files: LiveModelFiles(), access: LocalModelAccessGate(), log: UtterContracts.Log(service: Log.service))
    }
}
