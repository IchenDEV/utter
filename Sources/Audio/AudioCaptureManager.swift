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

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private(set) var lastRecordingURL: URL?
    private(set) var lastActivity = AudioCaptureActivity()
    /// Thresholds used for the next recording. Set from user sensitivity
    /// presets before `start(...)`; defaults preserve prior behavior.
    var thresholds = AudioActivityThresholds.default
    private var levelCallback: ((Float) -> Void)?
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?

    private var isRunning = false

    func cleanupLastRecording() {
        guard let url = lastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordingURL = nil
    }

    @discardableResult
    func start(
        deviceID: String?,
        levelUpdate: @escaping (Float) -> Void,
        bufferUpdate: ((AVAudioPCMBuffer) -> Void)? = nil
    ) -> Bool {
        if isRunning { stop() }
        cleanupLastRecording()
        lastActivity = AudioCaptureActivity(thresholds: thresholds)
        levelCallback = levelUpdate
        bufferCallback = bufferUpdate

        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authStatus == .authorized else {
            Log.error("[AudioCapture] microphone not authorized (status: \(authStatus.rawValue))")
            return false
        }

        if let deviceID, let uid = findDevice(id: deviceID) {
            setInputDevice(uid: uid)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.error("[AudioCapture] invalid input format: \(format)")
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentype_recording_\(UUID().uuidString).wav")
        lastRecordingURL = url

        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            Log.error("[AudioCapture] cannot create audio file: \(error.localizedDescription)")
            return false
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)

            let rms = Self.calculateRMS(buffer: buffer)
            self.lastActivity.record(rms: rms, frameCount: Int(buffer.frameLength))

            let level = Self.visualLevel(fromRMS: rms)
            self.levelCallback?(level)

            if let bufferCallback = self.bufferCallback {
                if let copiedBuffer = buffer.copied() {
                    bufferCallback(copiedBuffer)
                } else {
                    Log.error("[AudioCapture] unsupported format \(buffer.format.commonFormat.rawValue); dropping streaming buffer")
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            return true
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            Log.error("[AudioCapture] engine start failed: \(error.localizedDescription)")
            return false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        levelCallback = nil
        bufferCallback = nil
        isRunning = false
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
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)

        return deviceIDs.compactMap { deviceID -> (id: String, name: String)? in
            guard hasInputChannels(deviceID: deviceID) else { return nil }
            let name = deviceName(deviceID: deviceID) ?? "Unknown"
            let uid = deviceUID(deviceID: deviceID) ?? "\(deviceID)"
            return (id: uid, name: name)
        }
    }

    private func findDevice(id: String) -> String? {
        AudioCaptureManager.availableMicrophones().first { $0.id == id }?.id
    }

    private func setInputDevice(uid: String) {
        guard let deviceID = Self.audioDeviceID(forUID: uid) else { return }
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

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs)
        return deviceIDs.first { deviceUID(deviceID: $0) == uid }
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPointer.deallocate() }
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
    }

    private static func deviceUID(deviceID: AudioDeviceID) -> String? {
        getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func getStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let cf = value?.takeUnretainedValue() else { return nil }
        return cf as String
    }
}
