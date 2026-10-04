import UtterMediaContracts
import UtterContracts
import AVFoundation
import CoreAudio
import AudioToolbox

package final class AudioCaptureManager {
    let recordingLock = NSRecursiveLock()
    let log: Log
    let remoteEnabled: () -> Bool
    let engine = AVAudioEngine()
    var audioFile: AVAudioFile?
    var localLastRecordingURL: URL?
    var localLastActivity = AudioCaptureActivity()
    /// Thresholds used for the next recording. Set from user sensitivity
    /// presets before `start(...)`; defaults preserve prior behavior.
    package var thresholds = AudioActivityThresholds.default
    /// A voice-key session from the connected remote can supply audio instead of
    /// the selected CoreAudio device. Keyboard/API sessions remain local.
    package var remoteMicSource: (any RemoteCaptureSource)?
    /// Called on the main run loop after capture switches to a fallback input
    /// because the active device became unusable (for example, the lid closed).
    package var onAutoSwitch: (() -> Void)?
    /// Called on the main run loop when the active input was lost and no other
    /// usable input exists.
    package var onInputUnavailable: (() -> Void)?
    var usesRemoteMic = false
    var levelCallback: ((Float) -> Void)?
    var bufferCallback: ((AVAudioPCMBuffer) -> Void)?

    var isRunning = false
    var preferredInputUID: String?
    var activeInputUID: String?
    var failoverTimer: Timer?
    var recordingFormat: AVAudioFormat?
    var converter: AVAudioConverter?
    var converterSourceFormat: AVAudioFormat?
    var lastBufferFrameCount = 4096

    var tailDrainDuration: Duration {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        return AudioTailDrain.duration(frameCount: lastBufferFrameCount, sampleRate: recordingFormat?.sampleRate ?? 0)
    }

    package init(log: Log, remoteEnabled: @escaping () -> Bool) {
        self.log = log
        self.remoteEnabled = remoteEnabled
    }

    package var lastRecordingURL: URL? {
        usesRemoteMic ? remoteMicSource?.lastRecordingURL : localLastRecordingURL
    }

    package var lastActivity: AudioCaptureActivity {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        return usesRemoteMic
            ? (remoteMicSource?.lastActivity ?? AudioCaptureActivity(thresholds: thresholds))
            : localLastActivity
    }

    package func cleanupLastRecording() {
        if usesRemoteMic {
            remoteMicSource?.cleanupLastRecording()
            return
        }
        guard let url = localLastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        localLastRecordingURL = nil
    }

    @discardableResult
    package func start(
        deviceID: String?,
        levelUpdate: @escaping (Float) -> Void,
        bufferUpdate: ((AVAudioPCMBuffer) -> Void)? = nil
    ) -> AudioCaptureStartFailure? {
        if isRunning { stop() }
        cleanupLastRecording()
        usesRemoteMic = false
        localLastActivity = AudioCaptureActivity(thresholds: thresholds)
        lastBufferFrameCount = 4096
        levelCallback = levelUpdate
        bufferCallback = bufferUpdate

        // Only a session latched by the remote's voice key adopts its audio.
        if remoteEnabled(),
           let remoteMicSource,
           let token = remoteMicSource.currentSessionToken {
            remoteMicSource.thresholds = thresholds
            if remoteMicSource.start(token: token, levelUpdate: levelUpdate, bufferUpdate: bufferUpdate) {
                usesRemoteMic = true
                isRunning = true
                return nil
            }
            log.info("[AudioCapture] wireless remote unavailable; using the system input")
        }

        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authStatus == .authorized else {
            log.error("[AudioCapture] microphone not authorized (status: \(authStatus.rawValue))")
            return .permissionDenied
        }

        let devices = AudioInputDevices.available()
        let lidClosed = ClamshellState.isClosed
        switch AudioInputResolver.resolve(
            devices: devices,
            preferredUID: deviceID,
            systemDefaultUID: AudioInputDevices.systemDefaultUID(),
            lidClosed: lidClosed
        ) {
        case .unavailable:
            log.error("[AudioCapture] no usable input (lid closed: \(lidClosed))")
            return .noUsableInput
        case .use(let uid):
            preferredInputUID = deviceID
            activeInputUID = uid
            setInputDevice(uid: uid)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log.error("[AudioCapture] invalid input format: \(format)")
            return .engineFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentype_recording_\(UUID().uuidString).wav")
        localLastRecordingURL = url

        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            audioFile = file
            recordingFormat = file.processingFormat
        } catch {
            log.error("[AudioCapture] cannot create audio file: \(error.localizedDescription)")
            return .engineFailed
        }

        guard installCaptureTap() else {
            audioFile = nil
            return .engineFailed
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            log.error("[AudioCapture] engine start failed: \(error.localizedDescription)")
            return .engineFailed
        }

        isRunning = true
        startFailoverMonitor()
        return nil
    }

    package func stop() {
        guard isRunning else { return }
        stopFailoverMonitor()
        if usesRemoteMic {
            remoteMicSource?.stop()
            levelCallback = nil
            bufferCallback = nil
            isRunning = false
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recordingLock.lock()
        defer { recordingLock.unlock() }
        audioFile = nil
        recordingFormat = nil
        converter = nil
        converterSourceFormat = nil
        preferredInputUID = nil
        activeInputUID = nil
        levelCallback = nil
        bufferCallback = nil
        isRunning = false
    }

}
