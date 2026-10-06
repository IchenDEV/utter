import AVFoundation
import Foundation

extension AudioCaptureManager {
    /// How long a host-requested remote session may stay silent before the
    /// recording moves to the system input.
    static let remoteSilenceTimeout: TimeInterval = 3

    /// Records from the remote's own microphone. A recording started by the
    /// remote's voice key adopts that session; any other recording (shortcut,
    /// menu, developer API) asks the connected remote to open its microphone, so
    /// the remote works as the input even when the Mac's built-in mic is
    /// unreachable, such as with the lid closed.
    ///
    /// Returns false when the remote cannot supply audio; the caller then uses
    /// the system input.
    func startRemoteCapture() -> Bool {
        guard let remoteMicSource, let levelCallback else { return false }
        var token = remoteMicSource.currentSessionToken
        let hostRequested = token == nil
        if hostRequested, remoteMicSource.isAvailable {
            token = remoteMicSource.beginHostSession()
        }
        guard let token else {
            remoteMicSource.noteCapture(.systemRemoteUnavailable)
            return false
        }
        remoteMicSource.thresholds = thresholds
        guard remoteMicSource.start(token: token, levelUpdate: levelCallback, bufferUpdate: bufferCallback) else {
            if hostRequested { remoteMicSource.cancelSession() }
            Log.info("[AudioCapture] wireless remote unavailable; using the system input")
            remoteMicSource.noteCapture(.systemRemoteUnavailable)
            return false
        }
        usesRemoteMic = true
        isRunning = true
        remoteMicSource.noteCapture(.remote)
        if hostRequested { watchForRemoteSilence() }
        return true
    }

    /// A remote that is asleep or out of range accepts the open request but
    /// never streams. Without this the recording would stay silent.
    private func watchForRemoteSilence() {
        remoteSilenceTask?.cancel()
        remoteSilenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.remoteSilenceTimeout * 1_000_000_000))
            guard let self, !Task.isCancelled, self.isRunning, self.usesRemoteMic,
                  let remote = self.remoteMicSource, !remote.hasReceivedSamples else { return }
            self.fallBackFromSilentRemote(remote)
        }
    }

    private func fallBackFromSilentRemote(_ remote: RemoteMicCaptureManager) {
        Log.info("[AudioCapture] remote microphone sent no audio; switching to the system input")
        remote.cancelSession()
        remote.noteCapture(.systemRemoteSilent)
        usesRemoteMic = false
        isRunning = false
        if startLocal(deviceID: requestedDeviceID) == nil {
            onAutoSwitch?()
        } else {
            onInputUnavailable?()
        }
    }
}
