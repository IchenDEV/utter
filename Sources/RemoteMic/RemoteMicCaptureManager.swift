import AVFoundation
import Foundation

/// Capture source backed by the wireless remote's ATVV audio stream.
///
/// It mirrors `AudioCaptureManager`'s recording surface (activity, level
/// callback, streamed buffers, temp WAV) so the voice pipeline can swap sources
/// without knowing where the samples came from. Samples arrive as 16 kHz mono
/// Int16 and are written as 16 kHz mono Float32, which is the format every
/// speech engine normalizes to anyway.
final class RemoteMicCaptureManager {
    static let shared = RemoteMicCaptureManager()

    private let bridge: XiaomiRemoteMicBridge
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private(set) var lastRecordingURL: URL?
    private(set) var lastActivity = AudioCaptureActivity()
    var thresholds = AudioActivityThresholds.default

    private var audioFile: AVAudioFile?
    private var levelCallback: ((Float) -> Void)?
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?
    private var isRunning = false

    init(bridge: XiaomiRemoteMicBridge = .shared) {
        self.bridge = bridge
    }

    var isAvailable: Bool { bridge.state.isReady }
    var state: RemoteMicBridgeState { bridge.state }

    func activate() {
        bridge.activate()
    }

    func deactivate() {
        bridge.deactivate()
    }

    func cleanupLastRecording() {
        guard let url = lastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordingURL = nil
    }

    @discardableResult
    func start(
        levelUpdate: @escaping (Float) -> Void,
        bufferUpdate: ((AVAudioPCMBuffer) -> Void)? = nil
    ) -> Bool {
        if !bridge.state.isReady { bridge.activate() }
        guard bridge.state.isReady else { return false }

        if isRunning { stop() }
        cleanupLastRecording()
        lastActivity = AudioCaptureActivity(thresholds: thresholds)
        levelCallback = levelUpdate
        bufferCallback = bufferUpdate

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentype_remotemic_\(UUID().uuidString).wav")
        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            Log.error("[RemoteMic] cannot create recording: \(error.localizedDescription)")
            return false
        }
        lastRecordingURL = url

        bridge.onSamples = { [weak self] samples in
            self?.ingest(samples)
        }
        guard bridge.beginCapture() else {
            audioFile = nil
            lastRecordingURL = nil
            return false
        }
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        bridge.endCapture()
        bridge.onSamples = nil
        audioFile = nil
        levelCallback = nil
        bufferCallback = nil
    }

    private func ingest(_ samples: [Int16]) {
        guard isRunning, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            for index in samples.indices {
                channel[index] = Float(samples[index]) / 32_768.0
            }
        }

        try? audioFile?.write(from: buffer)

        let rms = Self.rms(of: buffer)
        lastActivity.record(rms: rms, frameCount: Int(buffer.frameLength))
        levelCallback?(Self.visualLevel(fromRMS: rms))
        if let bufferCallback, let copied = buffer.copied() {
            bufferCallback(copied)
        }
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0, let channel = buffer.floatChannelData?[0] else { return 0 }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        return sqrt(sum / Float(count))
    }

    private static func visualLevel(fromRMS rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        return max(min((db + 50) / 50, 1.0), 0.0)
    }
}
