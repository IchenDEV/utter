import UtterPresentationContracts
import UtterContracts
import AVFoundation
import CoreAudio
import AudioToolbox

struct AudioCaptureActivity: Equatable {
    let thresholds: AudioActivityThresholds

    private(set) var bufferCount = 0
    private(set) var frameCount = 0
    private(set) var maxRMS: Float = 0
    private var weightedRMSSum: Double = 0

    init(thresholds: AudioActivityThresholds = .default) {
        self.thresholds = thresholds
    }

    var averageRMS: Float {
        guard frameCount > 0 else { return 0 }
        return Float(weightedRMSSum / Double(frameCount))
    }

    var hasMeaningfulAudio: Bool {
        guard frameCount > 0 else { return false }
        let gate = thresholds.gate
        return averageRMS >= gate.minimumAverageRMS || maxRMS >= gate.minimumPeakRMS
    }

    var hasWeakSpeechEvidence: Bool {
        guard frameCount > 0 else { return true }
        let weak = thresholds.weakSpeechEvidence
        return averageRMS < weak.averageRMS && maxRMS < weak.peakRMS
    }

    mutating func record(rms: Float, frameCount: Int) {
        guard frameCount > 0 else { return }
        let normalizedRMS = max(0, rms)
        bufferCount += 1
        self.frameCount += frameCount
        maxRMS = max(maxRMS, normalizedRMS)
        weightedRMSSum += Double(normalizedRMS) * Double(frameCount)
    }
}

/// Why a local capture could not start. Remote wiring maps these to localized
/// messages; the pipeline distinguishes "no usable input" from permission loss.
enum AudioCaptureStartFailure: Error, Equatable {
    case permissionDenied
    case noUsableInput
    case engineFailed
}

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var localLastRecordingURL: URL?
    private var localLastActivity = AudioCaptureActivity()
    /// Thresholds used for the next recording. Set from user sensitivity
    /// presets before `start(...)`; defaults preserve prior behavior.
    var thresholds = AudioActivityThresholds.default
    /// A voice-key session from the connected remote can supply audio instead of
    /// the selected CoreAudio device. Keyboard/API sessions remain local.
    var remoteMicSource: RemoteMicCaptureManager?
    /// Called on the main run loop after capture switches to a fallback input
    /// because the active device became unusable (for example, the lid closed).
    var onAutoSwitch: (() -> Void)?
    /// Called on the main run loop when the active input was lost and no other
    /// usable input exists.
    var onInputUnavailable: (() -> Void)?
    private var usesRemoteMic = false
    private var levelCallback: ((Float) -> Void)?
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?

    private var isRunning = false
    private var preferredInputUID: String?
    private var activeInputUID: String?
    private var failoverTimer: Timer?
    private var recordingFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    var lastRecordingURL: URL? {
        usesRemoteMic ? remoteMicSource?.lastRecordingURL : localLastRecordingURL
    }

    var lastActivity: AudioCaptureActivity {
        usesRemoteMic
            ? (remoteMicSource?.lastActivity ?? AudioCaptureActivity(thresholds: thresholds))
            : localLastActivity
    }

    func cleanupLastRecording() {
        if usesRemoteMic {
            remoteMicSource?.cleanupLastRecording()
            return
        }
        guard let url = localLastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        localLastRecordingURL = nil
    }

    @discardableResult
    func start(
        deviceID: String?,
        levelUpdate: @escaping (Float) -> Void,
        bufferUpdate: ((AVAudioPCMBuffer) -> Void)? = nil
    ) -> AudioCaptureStartFailure? {
        if isRunning { stop() }
        cleanupLastRecording()
        usesRemoteMic = false
        localLastActivity = AudioCaptureActivity(thresholds: thresholds)
        levelCallback = levelUpdate
        bufferCallback = bufferUpdate

        // Only a session latched by the remote's voice key adopts its audio.
        if AppSettings.shared.remoteMicEnabled,
           let remoteMicSource,
           let token = remoteMicSource.currentSessionToken {
            remoteMicSource.thresholds = thresholds
            if remoteMicSource.start(token: token, levelUpdate: levelUpdate, bufferUpdate: bufferUpdate) {
                usesRemoteMic = true
                isRunning = true
                return nil
            }
            Log.info("[AudioCapture] wireless remote unavailable; using the system input")
        }

        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authStatus == .authorized else {
            Log.error("[AudioCapture] microphone not authorized (status: \(authStatus.rawValue))")
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
            Log.error("[AudioCapture] no usable input (lid closed: \(lidClosed))")
            return .noUsableInput
        case .use(let uid):
            preferredInputUID = deviceID
            activeInputUID = uid
            setInputDevice(uid: uid)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.error("[AudioCapture] invalid input format: \(format)")
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
            Log.error("[AudioCapture] cannot create audio file: \(error.localizedDescription)")
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
            Log.error("[AudioCapture] engine start failed: \(error.localizedDescription)")
            return .engineFailed
        }

        isRunning = true
        startFailoverMonitor()
        return nil
    }

    func stop() {
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

    // MARK: - Capture tap and file writing

    private func installCaptureTap() -> Bool {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.error("[AudioCapture] invalid input format: \(format)")
            return false
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.write(buffer)

            let rms = Self.calculateRMS(buffer: buffer)
            self.localLastActivity.record(rms: rms, frameCount: Int(buffer.frameLength))
            self.levelCallback?(Self.visualLevel(fromRMS: rms))

            if let bufferCallback = self.bufferCallback {
                if let copiedBuffer = buffer.copied() {
                    bufferCallback(copiedBuffer)
                } else {
                    Log.error("[AudioCapture] unsupported format \(buffer.format.commonFormat.rawValue); dropping streaming buffer")
                }
            }
        }
        return true
    }

    /// Writes a buffer to the recording file, converting when a fallback device
    /// produced a different sample rate or channel layout.
    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile, let target = recordingFormat else { return }
        if buffer.format == target {
            try? audioFile.write(from: buffer)
            return
        }
        guard let converted = convert(buffer, to: target) else { return }
        try? audioFile.write(from: converted)
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converterSourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterSourceFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            Log.error("[AudioCapture] format conversion failed: \(error.localizedDescription)")
            return nil
        }
        return output
    }

    // MARK: - Mid-session failover

    private func startFailoverMonitor() {
        stopFailoverMonitor()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.evaluateInputHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        failoverTimer = timer
    }

    private func stopFailoverMonitor() {
        failoverTimer?.invalidate()
        failoverTimer = nil
    }

    private func evaluateInputHealth() {
        guard isRunning, !usesRemoteMic else { return }
        let action = MicFailoverDecision.decide(
            activeUID: activeInputUID,
            devices: AudioInputDevices.available(),
            preferredUID: preferredInputUID,
            systemDefaultUID: AudioInputDevices.systemDefaultUID(),
            lidClosed: ClamshellState.isClosed
        )
        switch action {
        case .keep:
            break
        case .switchTo(let uid):
            switchInput(to: uid)
        case .fail:
            handleInputUnavailable()
        }
    }

    private func switchInput(to uid: String) {
        let name = AudioInputDevices.available().first(where: { $0.uid == uid })?.name ?? uid
        Log.info("[AudioCapture] switching to fallback input")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setInputDevice(uid: uid)
        guard installCaptureTap() else {
            handleInputUnavailable()
            return
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Log.error("[AudioCapture] fallback engine start failed: \(error.localizedDescription)")
            handleInputUnavailable()
            return
        }
        activeInputUID = uid
        Log.info("[AudioCapture] fallback input active: \(name)")
        onAutoSwitch?()
    }

    private func handleInputUnavailable() {
        Log.error("[AudioCapture] active input lost with no fallback")
        stop()
        onInputUnavailable?()
    }

    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0

        if let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for i in 0..<count { sum += data[i] * data[i] }
            }
            return sqrt(sum / Float(max(count * channelCount, 1)))
        }

        if let channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for i in 0..<count {
                    let sample = Float(data[i]) / Float(Int16.max)
                    sum += sample * sample
                }
            }
            return sqrt(sum / Float(max(count * channelCount, 1)))
        }

        return 0
    }

    private static func visualLevel(fromRMS rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = (db + 50) / 50   // map -50dB..0dB → 0..1
        return max(min(normalized, 1.0), 0.0)
    }

    // MARK: - Device Management

    static func availableMicrophones() -> [(id: String, name: String)] {
        AudioInputDevices.available().map { (id: $0.uid, name: $0.name) }
    }

    private func setInputDevice(uid: String) {
        guard let deviceID = AudioInputDevices.deviceID(forUID: uid) else { return }
        guard let audioUnit = engine.inputNode.audioUnit else { return }
        var id = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }
}
