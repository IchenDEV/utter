import UtterMediaContracts
import UtterContracts
import AVFoundation
import Foundation

/// Capture source backed by the wireless remote's ATVV audio stream.
///
/// It mirrors `AudioCaptureManager`'s recording surface (activity, level
/// callback, streamed buffers, temp WAV) so the voice pipeline can swap sources
/// without knowing where the samples came from. Samples arrive as 16 kHz mono
/// Int16 and are written as 16 kHz mono Float32, which is the format every
/// speech engine normalizes to anyway.
package final class RemoteMicCaptureManager: RemoteCaptureSource {

    private let log: UtterContracts.Log
    private let bridge: XiaomiRemoteMicBridge
    private let temporaryDirectory: URL
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    package private(set) var lastRecordingURL: URL?
    package private(set) var lastActivity = AudioCaptureActivity()
    package var thresholds = AudioActivityThresholds.default

    private var isClosed = false
    private var audioFile: AVAudioFile?
    private var levelCallback: ((Float) -> Void)?
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?
    package private(set) var isRunning = false

    package init(bridge: XiaomiRemoteMicBridge, log: UtterContracts.Log, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.bridge = bridge
        self.log = log
        self.temporaryDirectory = temporaryDirectory
    }

    package var isAvailable: Bool { bridge.state.isReady }
    package var state: RemoteMicBridgeState { bridge.state }
    /// The latched voice-key session this source would commit, if any.
    package var currentSessionToken: UInt64? { bridge.currentSessionToken }

    package func activate() {
        guard !isClosed else { return }
        bridge.activate()
    }

    package func deactivate() {
        bridge.deactivate()
    }

    package func cleanupLastRecording() {
        guard let url = lastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordingURL = nil
    }

    /// Prepares capture for a latched voice-key session.
    ///
    /// Returns `false` when the session was released or the remote is not usable,
    /// in which case the caller must not record. The preparatory work (temp file,
    /// readiness) is synchronous today, but is awaited so a future model load on
    /// this path does not change the caller's contract.
    package func startSession(token: UInt64) async -> Bool {
        prepareCapture(token: token)
    }

    /// Abandons an in-flight or latched session, releasing every trace so the
    /// pipeline can fall back or stay idle without a latent want.
    ///
    /// This discards the recording, so it must only be used *before* the
    /// pipeline commits to recording — never on a normal stop, where the WAV is
    /// still needed for transcription. Use `stop()` for a committed recording.
    package func cancelSession() {
        guard isRunning || bridge.isSessionLive else { return }
        tearDownFailedStart()
    }

    /// True when capture has committed and a recording file exists.
    package var hasActiveRecording: Bool { isRunning && audioFile != nil }

    /// The synchronous startup body shared by the session and direct paths.
    @discardableResult
    package func prepareCapture(token: UInt64) -> Bool {
        guard !isClosed, currentSessionToken == token else { return false }
        if isRunning { stop() }
        cleanupLastRecording()
        lastActivity = AudioCaptureActivity(thresholds: thresholds)
        levelCallback = nil
        bufferCallback = nil
        return true
    }

    /// Starts a capture for the latched voice-key session.
    ///
    /// `token` is the latch the caller observed; if the session was released or
    /// superseded while the pipeline was starting, this returns `false` and the
    /// caller must not begin recording (and must not fall back either, because
    /// the user already let go).
    @discardableResult
    package func start(
        token: UInt64,
        levelUpdate: @escaping (Float) -> Void,
        bufferUpdate: ((AVAudioPCMBuffer) -> Void)? = nil
    ) -> Bool {
        guard !isClosed, currentSessionToken == token else { return false }
        if !bridge.state.isReady { bridge.activate() }
        guard bridge.state.isReady else { return false }

        if isRunning { stop() }
        cleanupLastRecording()
        lastActivity = AudioCaptureActivity(thresholds: thresholds)
        levelCallback = levelUpdate
        bufferCallback = bufferUpdate

        let url = temporaryDirectory
            .appendingPathComponent("opentype_remotemic_\(UUID().uuidString).wav")
        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            log.error("[RemoteMic] cannot create recording: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            levelCallback = nil
            bufferCallback = nil
            return false
        }
        lastRecordingURL = url

        bridge.onSamples = { [weak self] samples in
            self?.ingest(samples)
        }

        // Commits the latched session and hands back any audio buffered before
        // the pipeline was ready. If the session was released meanwhile, undo
        // everything so a later readiness cannot adopt it.
        guard let preRolled = bridge.beginCapture(token: token) else {
            tearDownFailedStart()
            return false
        }
        isRunning = true
        if !preRolled.isEmpty {
            ingest(preRolled)
        }
        return true
    }

    /// Releases every trace of an attempted start so the bridge cannot adopt a
    /// session the caller has already replaced with the system input.
    private func tearDownFailedStart() {
        bridge.onSamples = nil
        bridge.endCapture()
        audioFile = nil
        cleanupLastRecording()
        levelCallback = nil
        bufferCallback = nil
        isRunning = false
    }

    package func revoke() {
        guard !isClosed else { return }
        isClosed = true
        levelCallback = nil
        bufferCallback = nil
    }

    package func close() {
        revoke()
        stop()
        cleanupLastRecording()
    }

    package func stop() {
        guard isRunning else { return }
        isRunning = false
        bridge.endCapture()
        bridge.onSamples = nil
        audioFile = nil
        levelCallback = nil
        bufferCallback = nil
    }

    /// Mirrors `AudioCaptureManager.lastActivity` semantics: an empty session
    /// must not report meaningful audio.
    package var hasRecordedActivity: Bool { lastActivity.frameCount > 0 }

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
