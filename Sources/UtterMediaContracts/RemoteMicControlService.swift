import Foundation
import UtterContracts
import UtterRuntime

@MainActor
package protocol RemoteMicControlService: AnyObject {
    var state: RemoteMicBridgeState { get }
    var diagnostics: RemoteMicDiagnostics { get }
    func reconnect()
    func observeDiagnostics(_ callback: @escaping (RemoteMicDiagnostics) -> Void) -> UUID
    func setEnabled(_ enabled: Bool)
    func setVoiceCallbacks(pressed: ((UInt64) -> Void)?, released: (() -> Void)?, stopped: (() -> Void)?)
    func observe(_ callback: @escaping (RemoteMicBridgeState) -> Void) -> UUID
    func removeObserver(_ id: UUID)
}

extension RemoteMicServices {
    package static let control = ServiceKey<any RemoteMicControlService>("remote-mic.control")
}
