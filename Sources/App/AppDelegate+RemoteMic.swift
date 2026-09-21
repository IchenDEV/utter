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
    }

    private func applyRemoteMicSetting(_ enabled: Bool) {
        if enabled {
            RemoteMicCaptureManager.shared.activate()
        } else {
            RemoteMicCaptureManager.shared.deactivate()
        }
    }
}
