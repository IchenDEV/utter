import Combine
import Foundation

@MainActor
extension AppDelegate {
    /// Keeps the wireless-remote Bluetooth link in sync with the setting so the
    /// remote is already connected before the first recording starts.
    func observeRemoteMicSetting() {
        let settings = AppSettings.shared
        applyRemoteMicSetting(settings.remoteMicEnabled)
        settings.$remoteMicEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.applyRemoteMicSetting(enabled)
            }
            .store(in: &cancellables)
        observeRemoteMicVoiceKey()
    }

    /// Enabling or disabling the feature must not leave a recording running.
    private func applyRemoteMicSetting(_ enabled: Bool) {
        if enabled {
            RemoteMicCaptureManager.shared.activate()
        } else {
            RemoteMicCaptureManager.shared.cancelSession()
            RemoteMicCaptureManager.shared.deactivate()
        }
    }

    /// The remote's voice key arrives on the ATVV control channel while the
    /// feature is active, so it drives the same recording path as the configured
    /// hotkey. Holding the key records; releasing it stops.
    ///
    /// The bridge latches the session synchronously and hands over a token. The
    /// pipeline start is asynchronous, so a release that arrives first cancels
    /// the pending start instead of being ignored.
    private func observeRemoteMicVoiceKey() {
        let bridge = XiaomiRemoteMicBridge.shared
        bridge.onVoiceKeyPressed = { [weak self] token in
            guard let self, AppSettings.shared.remoteMicEnabled else { return }
            self.beginRemoteMicSession(token: token)
        }
        bridge.onVoiceKeyReleased = { [weak self] in
            guard let self, AppSettings.shared.remoteMicEnabled else { return }
            self.releaseRemoteMicSession()
        }
    }

    private func beginRemoteMicSession(token: UInt64) {
        // A new press supersedes any previous start that is still running.
        remoteMicStartTask?.cancel()
        remoteMicPendingToken = token
        let capture = RemoteMicCaptureManager.shared
        remoteMicStartTask = Task { @MainActor [weak self] in
            let started = await capture.startSession(token: token)
            guard let self, !Task.isCancelled else { return }
            // Released or superseded while starting: do not begin recording.
            guard self.remoteMicPendingToken == token else {
                capture.cancelSession()
                return
            }
            guard started else {
                self.remoteMicPendingToken = nil
                return
            }
            self.remoteMicStartTask = nil
            self.startRecording(action: .dictation)
        }
    }

    private func releaseRemoteMicSession() {
        let hadPending = remoteMicPendingToken != nil
        remoteMicPendingToken = nil
        remoteMicStartTask?.cancel()
        remoteMicStartTask = nil
        RemoteMicCaptureManager.shared.cancelSession()
        // Only stop the pipeline if a session actually reached recording.
        if !hadPending || RemoteMicCaptureManager.shared.isRunning {
            stopRecording()
        }
    }
}
