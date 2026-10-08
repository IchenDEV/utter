import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Fails the current attempt after `seconds` unless `isSatisfied` says the
    /// step completed. Runs on the main actor so the check races nothing.
    func startTimeout(
        seconds: TimeInterval,
        generation expected: UInt64,
        reason: @escaping @autoclosure () -> String,
        isSatisfied: @escaping () -> Bool
    ) {
        cancelTimeout()
        timeoutTask = ownedTask { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled, self.generation == expected else { return }
            guard !isSatisfied() else { return }
            self.failAttempt(reason: reason())
        }
    }

    func failAttempt(reason: String) {
        state = .failed(reason: reason)
        resetStream()
        closeMicrophoneIfNeeded()
        retireCurrentCentral()
        resetPeripheral()
        scheduleReconnect()
    }

    func scheduleReconnect() {
        guard isActive else { return }
        cancelReconnect()
        reconnectAttempts += 1
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempts, 5))))
        reconnectTask = ownedTask { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.beginScan()
        }
    }

    func handleDisconnect() {
        if session.invalidate() {
            onStreamStopped?()
            onVoiceKeyReleased?()
        }
        resetStream()
        handshake.reset()
        microphoneOpened = false
        cancelTimeout()
        retireCurrentCentral()
        resetPeripheral()
        if isActive { scheduleReconnect() }
    }
}
