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

    private func applyRemoteMicSetting(_ enabled: Bool) {
        if enabled {
            RemoteMicCaptureManager.shared.activate()
        } else {
            RemoteMicCaptureManager.shared.deactivate()
        }
    }

    /// The remote's voice key arrives on the ATVV control channel while the
    /// feature is active, so it drives the same recording path as the configured
    /// hotkey. Holding the key records; releasing it stops.
    private func observeRemoteMicVoiceKey() {
        let bridge = XiaomiRemoteMicBridge.shared
        bridge.onVoiceKeyPressed = { [weak self] in
            guard let self, AppSettings.shared.remoteMicEnabled else { return }
            self.startRecording(action: .dictation)
        }
        bridge.onVoiceKeyReleased = { [weak self] in
            guard let self, AppSettings.shared.remoteMicEnabled else { return }
            self.stopRecording()
        }
    }
}
