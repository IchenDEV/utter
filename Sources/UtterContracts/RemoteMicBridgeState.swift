import Foundation

package enum RemoteMicBridgeState: Equatable {
    case idle
    case unsupported
    case unauthorized
    case scanning
    case connecting
    case ready(deviceName: String)
    case failed(reason: String)

    package var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    package var summary: String {
        switch self {
        case .idle: return L("remote_mic.state.idle")
        case .unsupported: return L("remote_mic.state.unsupported")
        case .unauthorized: return L("remote_mic.state.unauthorized")
        case .scanning: return L("remote_mic.state.scanning")
        case .connecting: return L("remote_mic.state.connecting")
        case let .ready(deviceName): return String(format: L("remote_mic.state.ready"), deviceName)
        case let .failed(reason): return String(format: L("remote_mic.state.failed"), reason)
        }
    }
}
