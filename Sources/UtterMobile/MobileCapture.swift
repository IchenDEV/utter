#if os(iOS)
import Foundation
import AVFoundation
import UtterRuntime
import UtterContracts
import UtterMediaContracts

#if DEBUG
@MainActor
public enum MobileCaptureDiagnostics {
    // Capture-owned observations, not a query of the system's global microphone state.
    public internal(set) static var engineRunning = false
    public internal(set) static var sessionDeactivated = false
    public internal(set) static var completedFrames = 0
}
#endif

@MainActor
final class MobileCapture: CaptureService {
    private var active: MobileRecording?

    func begin(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws -> any OwnedRecording {
        guard active == nil else { throw CaptureError.busy }
        guard case .local = request.source else { throw CaptureError.remoteUnavailable }
        try Task.checkCancellation()
        let recording = try MobileRecording(thresholds: request.thresholds, callbacks: callbacks) { [weak self] in self?.active = nil }
        active = recording
        return recording
    }
}

@MainActor
private final class MobileRecording: OwnedRecording {
    private let engine = AVAudioEngine()
    private let writer: RecordingWriter
    private let release: () -> Void
    private var stopped = false
    private var revoked = false
    private var observers: [NSObjectProtocol] = []
    private let callbacks: CaptureCallbacks

    init(thresholds: AudioActivityThresholds, callbacks: CaptureCallbacks, release: @escaping () -> Void) throws {
        self.release = release; self.callbacks = callbacks
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP])
        try session.setActive(true)
        #if DEBUG
        MobileCaptureDiagnostics.sessionDeactivated = false
        #endif
        var installedTap = false
        var pendingWriter: RecordingWriter?
        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MobileError.localUnavailable }
            writer = try RecordingWriter(format: format, thresholds: thresholds)
            pendingWriter = writer
            let writer = self.writer
            let live = callbacks.buffer
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in writer.append(buffer); live?(buffer) }
            installedTap = true
            try engine.start()
            #if DEBUG
            MobileCaptureDiagnostics.engineRunning = engine.isRunning
            #endif
        } catch {
            if installedTap { engine.inputNode.removeTap(onBus: 0) }
            engine.stop()
            if let pendingWriter {
                _ = pendingWriter.finish()
                try? FileManager.default.removeItem(at: pendingWriter.url)
            }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                Task { @MainActor [weak self] in
                    guard let self, !self.stopped, !self.revoked else { return }
                    // Our own category activation can arrive after the input tap starts.
                    if name == AVAudioSession.routeChangeNotification,
                       reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue,
                       AVAudioSession.sharedInstance().category == .playAndRecord { return }
                    self.callbacks.inputUnavailable()
                }
            })
        }
    }

    func finish() async throws -> CapturedAudio {
        try Task.checkCancellation()
        guard !revoked else { throw CancellationError() }
        let result = stop()
        if let error = result.error { throw error }
        return CapturedAudio(url: writer.url, activity: result.activity)
    }

    func revoke() {
        revoked = true
        removeObservers()
    }

    func stopCapture() async {
        revoke()
        _ = stop()
    }

    func close() async {
        await stopCapture()
        try? FileManager.default.removeItem(at: writer.url)
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func stop() -> (activity: AudioCaptureActivity, error: Error?) {
        if !stopped {
            stopped = true
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            removeObservers()
            release()
        }
        let result = writer.finish()
        #if DEBUG
        MobileCaptureDiagnostics.engineRunning = engine.isRunning
        MobileCaptureDiagnostics.completedFrames = result.activity.frameCount
        #endif
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { return (result.activity, error) }
        #if DEBUG
        MobileCaptureDiagnostics.sessionDeactivated = true
        #endif
        return result
    }
}

private final class RecordingWriter: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var activity: AudioCaptureActivity
    private var failure: Error?

    init(format: AVAudioFormat, thresholds: AudioActivityThresholds) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UtterRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        activity = AudioCaptureActivity(thresholds: thresholds)
        do {
            file = try AVAudioFile(forWriting: url, settings: format.settings)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        } catch {
            file = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let file, failure == nil else { return }
        do { try file.write(from: buffer) }
        catch { failure = error; return }
        let count = Int(buffer.frameLength)
        if let samples = buffer.floatChannelData?.pointee, count > 0 {
            let squares = (0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
            activity.record(rms: sqrt(squares / Float(count)), frameCount: count)
        }
    }

    func finish() -> (activity: AudioCaptureActivity, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        file = nil
        return (activity, failure)
    }
}
#endif
