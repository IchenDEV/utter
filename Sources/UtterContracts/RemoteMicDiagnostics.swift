import Foundation

package enum RemoteMicDiscoverySource: Equatable, Sendable {
    case connectedVoiceService
    case connectedHID
    case scan
}

package enum RemoteMicCaptureSource: Equatable, Sendable {
    case remote
    case systemRemoteUnavailable
    case systemRemoteSilent
}

package struct RemoteMicDiagnostics: Equatable, Sendable {
    package var discovery: RemoteMicDiscoverySource?
    package var modelNumber: String?
    package var lowNibbleFirst: Bool
    package var lastCapture: RemoteMicCaptureSource?

    package init(discovery: RemoteMicDiscoverySource? = nil, modelNumber: String? = nil,
                 lowNibbleFirst: Bool = false, lastCapture: RemoteMicCaptureSource? = nil) {
        self.discovery = discovery
        self.modelNumber = modelNumber
        self.lowNibbleFirst = lowNibbleFirst
        self.lastCapture = lastCapture
    }
}
