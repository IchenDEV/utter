import UtterContracts
import UtterRemoteInference

extension VolcSpeechEngine {
    convenience init(appKey: String, accessKey: String, resourceId: String) {
        self.init(appKey: appKey, accessKey: accessKey, resourceId: resourceId, log: UtterContracts.Log(service: Log.service))
    }
}
