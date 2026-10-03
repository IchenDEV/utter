import UtterContracts
import UtterRemoteInference

extension RemoteLLMClient {
    init() {
        self.init(transport: URLSessionRemoteTransport(), log: UtterContracts.Log(service: Log.service))
    }
}
