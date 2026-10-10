import Foundation
import UtterContracts
import UtterMediaContracts

@MainActor
final class LocalCaptureDriver: CaptureDriver {
    private let capture: AudioCaptureManager
    init(log: Log, remote: (any RemoteCaptureSource)? = nil) {
        capture = AudioCaptureManager(log: log, remoteEnabled: { remote != nil })
        capture.remoteMicSource = remote
    }

    func start(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws {
        guard case .local(let deviceID) = request.source else { throw CaptureError.remoteUnavailable }
        try Task.checkCancellation()
        capture.thresholds = request.thresholds
        capture.onAutoSwitch = callbacks.switchedInput
        capture.onInputUnavailable = callbacks.inputUnavailable
        if let error = capture.start(deviceID: deviceID, levelUpdate: callbacks.level, bufferUpdate: callbacks.buffer) {
            throw CaptureError.startFailed(error)
        }
    }
    func stop(flushTail: Bool) async -> CapturedAudio {
        if flushTail, capture.isRunning {
            try? await Task.sleep(for: capture.tailDrainDuration)
        }
        let silenceTask = capture.remoteSilenceTask
        capture.stop()
        await silenceTask?.value
        return CapturedAudio(url: capture.lastRecordingURL, activity: capture.lastActivity)
    }
    func cleanup() async {
        capture.onAutoSwitch = nil
        capture.onInputUnavailable = nil
        capture.cleanupLastRecording()
    }
}

@MainActor
final class RemoteCaptureDriver: CaptureDriver {
    private let source: any RemoteCaptureSource
    private var ownsCapture = false
    init(source: any RemoteCaptureSource) { self.source = source }

    func start(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws {
        guard case .remote(let token) = request.source else { throw CaptureError.remoteUnavailable }
        try Task.checkCancellation()
        guard source.currentSessionToken == token else { throw CaptureError.remoteUnavailable }
        source.thresholds = request.thresholds
        guard source.start(token: token, levelUpdate: callbacks.level, bufferUpdate: callbacks.buffer) else {
            throw CaptureError.remoteUnavailable
        }
        ownsCapture = true
        source.noteCapture(.remote)
    }
    func stop(flushTail: Bool) async -> CapturedAudio {
        guard ownsCapture else { return CapturedAudio(url: nil, activity: AudioCaptureActivity()) }
        source.stop()
        return CapturedAudio(url: source.lastRecordingURL, activity: source.lastActivity)
    }
    func cleanup() async {
        guard ownsCapture else { return }
        source.cleanupLastRecording()
        ownsCapture = false
    }
}
