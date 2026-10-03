import UtterContracts
import UtterRemoteMic

extension XiaomiRemoteMicBridge {
    static let shared = XiaomiRemoteMicBridge()

    convenience init() {
        self.init(gainDB: { AppSettings.shared.remoteMicGainDB })
    }

    static func isSessionCurrent(_ token: UInt64) -> Bool {
        shared.currentSessionToken == token
    }
}

extension RemoteMicCaptureManager: RemoteMicReleaseTarget {
    static let shared = RemoteMicCaptureManager()

    convenience init(bridge: XiaomiRemoteMicBridge = .shared) {
        self.init(bridge: bridge, log: UtterContracts.Log(service: OpenType.Log.service))
    }
}
