import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    // MARK: - Lifecycle

    package func activate() {
        guard !isClosed, !isActive else { return }
        isActive = true
        reconnectAttempts = 0
        guard centralTransport == nil else {
            beginScan()
            return
        }
        if case .quiescing = centralLifecycle {
            // `deactivate()` has already issued cancellation. Do not create a
            // new manager until the old context reports terminal completion.
            scanRequestedWhileQuiescing = true
            return
        }
        installCentralTransport()
    }

    package func deactivate() {
        isActive = false
        // Closing the feature must end a live session, not leave Utter recording.
        let wasLive = session.invalidate()
        if wasLive {
            onStreamStopped?()
            onVoiceKeyReleased?()
        }
        cancelReconnect()
        cancelTimeout()
        generation &+= 1
        closeMicrophoneIfNeeded()
        resetStream()
        retireCurrentCentral()
        resetPeripheral()
        state = .idle
    }

    /// Commits the latched voice-key session to the capture pipeline and returns
    /// any audio buffered before it was ready, in order.
    ///
    /// `token` is the latch the caller observed when it started; if the session
    /// was released or superseded meanwhile this returns `nil`, and the caller
    /// must not begin recording.
    package func beginCapture(token: UInt64) -> [Int16]? {
        if !isActive { activate() }
        guard session.commitStart(token: token) else { return nil }
        guard peripheral?.state == .connected, handshake.isReady else {
            // Not usable yet: drop the latched session so a later readiness does
            // not open the remote microphone for a session that fell back.
            _ = session.release()
            preRoll.reset()
            return nil
        }
        if !microphoneOpened { openMicrophoneIfNeeded() }
        let buffered = preRoll.drain().flatMap { $0 }
        return buffered
    }

    /// True while a voice-key session is latched or recording.
    package var isSessionLive: Bool { session.isLive }

    /// The latch of the current voice-key session, or nil when idle.
    package var currentSessionToken: UInt64? { session.isLive ? session.generation : nil }

    /// Test-only: latch a session without a real remote, so tests can drive the
    /// pipeline's post-load check through the real bridge predicate.
    package func beginSimulatedSessionForTesting() -> UInt64 {
        session.press()
    }

    /// Test-only: release the simulated session.
    @discardableResult
    package func endSimulatedSessionForTesting() -> Bool {
        session.release()
    }

    package func endCapture() {
        // Close exactly once, whatever the phase: a release during `starting`
        // must still close a microphone this bridge may have opened, and must
        // not leave `microphoneOpened` set for the next attempt.
        let wasLive = session.release()
        cancelExtend()
        if microphoneOpened || wasLive {
            closeMicrophoneIfNeeded()
        }
        if !session.isLive {
            preRoll.reset()
            accumulator.reset()
            pendingSync = nil
            decoder.reset()
        }
    }

    package func reconnectNow() {
        if isActive { deactivate() }
        activate()
    }

    package func noteCapture(_ source: RemoteMicCaptureSource) {
        diagnostics.lastCapture = source
    }

    package func beginHostSession() -> UInt64? {
        guard !isClosed, isActive, peripheral?.state == .connected, handshake.isReady else { return nil }
        return latchHostSession()
    }

    func latchHostSession() -> UInt64? {
        guard !session.isLive else { return nil }
        streamGainDB = gainDB()
        hostInitiated = true
        streamAnnounced = false
        return session.press()
    }
}
