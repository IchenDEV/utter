import UtterContracts
import UtterRemoteMic
import UtterPresentationContracts

extension XiaomiRemoteMicBridge {
    static let shared = XiaomiRemoteMicBridge()

    convenience init(legacySettings: AppSettings = .shared) {
        self.init(gainDB: { legacySettings.remoteMicGainDB })
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
