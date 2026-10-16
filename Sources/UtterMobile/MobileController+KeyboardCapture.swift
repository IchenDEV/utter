#if os(iOS)
import Foundation
import UtterKeyboardBridge

extension MobileController {
    var keyboardCaptureRunning: Bool {
        #if DEBUG
        status.captureFromApp == true && status.phase == .recording && MobileCaptureDiagnostics.engineRunning
        #else
        false
        #endif
    }

    #if DEBUG
    public func beginKeyboardCapture(id: UUID, documentID: UUID? = nil) throws {
        guard diagnosticText == nil, !standbyActive else { throw BridgeError.invalidTarget }
        try beginLocal(id: id)
        keyboardCaptureDocumentID = documentID
        status.captureFromApp = true
        publish()
    }
    #endif

    func attachKeyboardTarget(_ command: VoiceCommand) throws {
        #if DEBUG
        guard isEnabled, keyboardCaptureRunning, status.canAttachKeyboardTarget,
              status.requestID == command.captureRequestID, activeLease == nil,
              keyboardCaptureDocumentID == nil || keyboardCaptureDocumentID == command.lease.documentID else { throw BridgeError.invalidTarget }
        activeLease = command.lease
        status.leaseID = command.lease.id; status.documentID = command.lease.documentID
        watchLease(command.lease)
        publish()
        #else
        throw BridgeError.invalidTarget
        #endif
    }

    func watchLease(_ lease: KeyboardLease?) {
        watchdog?.cancel(); watchdog = nil
        guard let lease else { return }
        let request = status.requestID
        watchdog = Task { [weak self] in
            while let self, self.status.isBusy, self.status.requestID == request, !Task.isCancelled {
                do {
                    guard let current = try self.bridge?.lease(lease.id), current.generation == lease.generation,
                          current.documentID == lease.documentID else { await self.cancel(); return }
                    try await Task.sleep(for: .seconds(1))
                } catch { await self.cancel(); return }
            }
        }
    }
}
#endif
