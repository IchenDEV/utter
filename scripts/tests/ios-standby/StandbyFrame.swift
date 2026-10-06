import AVKit
import SwiftUI
import UtterKeyboardBridge

@MainActor
final class StandbyPausedRecorder {
    private var recorder: AVAudioRecorder?
    private var preparationID: UUID?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("standby-paused-recorder.caf")
    var isRecording: Bool { recorder?.isRecording == true }
    var isPrepared: Bool { recorder != nil }
    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    func prepareAndPause() async throws {
        let id = UUID()
        preparationID = id
        for _ in 0..<40 {
            guard preparationID == id else { throw CancellationError() }
            if UIApplication.shared.applicationState == .active { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard preparationID == id else { throw CancellationError() }
        guard UIApplication.shared.applicationState == .active,
              AVAudioApplication.shared.recordPermission == .granted else { throw BridgeError.unavailable }
        let current = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
        recorder = current
        do {
            guard current.prepareToRecord() else { throw BridgeError.unavailable }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            guard current.record(forDuration: 4) else { throw BridgeError.unavailable }
            try await Task.sleep(for: .seconds(3))
            guard preparationID == id, recorder === current else { throw CancellationError() }
            guard UIApplication.shared.applicationState == .active, current.isRecording else { throw BridgeError.unavailable }
            current.pause()
            guard !current.isRecording, current.currentTime > 1 else { throw BridgeError.unavailable }
        } catch {
            if preparationID == id, recorder === current { stop() }
            throw error
        }
    }

    func stop() {
        preparationID = nil
        recorder?.stop()
        if let recorder { _ = recorder.deleteRecording() }
        recorder = nil
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
struct ProbeSource: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
final class StandbyJournal {
    private var entries: [[String: Any]] = []
    private var fingerprint: Data?
    private var lastWrite = Date.distantPast
    static func erase() {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ichendev.utter.ios") else { return }
        for name in ["standby-probe.json", "Library/standby-probe.json", "Library/standby-journal.json"] {
            try? FileManager.default.removeItem(at: group.appendingPathComponent(name))
        }
    }
    func reset() { entries = []; fingerprint = nil; lastWrite = .distantPast }
    func write(_ value: [String: Any], group: URL) {
        var state = value
        for key in ["time", "backgroundTicks", "backgroundMaxGap", "backgroundSeconds", "recorderTime"] {
            state.removeValue(forKey: key)
        }
        guard let next = try? JSONSerialization.data(withJSONObject: state, options: .sortedKeys),
              next != fingerprint || Date().timeIntervalSince(lastWrite) >= 5 else { return }
        let directory = group.appendingPathComponent("Library", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Remove only this probe's superseded diagnostic, never bridge or user data.
            let old = group.appendingPathComponent("standby-probe.json")
            if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
            if entries.count < 2400 { entries.append(value) }
            try JSONSerialization.data(withJSONObject: entries).write(to: directory.appendingPathComponent("standby-journal.json"), options: [.atomic, .completeFileProtection])
            try JSONSerialization.data(withJSONObject: value).write(to: directory.appendingPathComponent("standby-probe.json"), options: [.atomic, .completeFileProtection])
            fingerprint = next; lastWrite = Date()
        } catch { print("STANDBY_JOURNAL failed: \((error as NSError).code)") }
    }
}

@MainActor
func prepareStandbyFrame(in content: AVPictureInPictureVideoCallViewController) throws {
    let video = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
    let display = AVSampleBufferDisplayLayer()
    display.frame = video.bounds
    video.layer.addSublayer(display)
    content.view.subviews.forEach { $0.removeFromSuperview() }
    content.view.addSubview(video)
    try enqueueStandbyFrame(on: display)
}

@MainActor
private func enqueueStandbyFrame(on display: AVSampleBufferDisplayLayer) throws {
    var pixel: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                              [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess,
          let pixel else { throw BridgeError.unavailable }
    CVPixelBufferLockBaseAddress(pixel, [])
    if let address = CVPixelBufferGetBaseAddress(pixel) {
        memset(address, 0x80, CVPixelBufferGetDataSize(pixel))
    }
    CVPixelBufferUnlockBaseAddress(pixel, [])
    var format: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
                                                        formatDescriptionOut: &format) == noErr,
          let format else { throw BridgeError.unavailable }
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
                                                   formatDescription: format, sampleTiming: &timing,
                                                   sampleBufferOut: &sample) == noErr,
          let sample else { throw BridgeError.unavailable }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
        let values = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(values, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    display.enqueue(sample)
}

@MainActor
final class StandbySampleSource: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    private let display = AVSampleBufferDisplayLayer()
    private var paused = false

    func reset() {
        paused = true
        if let timebase = display.controlTimebase { CMTimebaseSetRate(timebase, rate: 0) }
        display.flushAndRemoveImage()
        display.controlTimebase = nil
        display.removeFromSuperlayer()
    }

    func prepare(in view: UIView) throws -> AVPictureInPictureController.ContentSource {
        reset()
        paused = false
        display.frame = view.bounds
        view.layer.addSublayer(display)
        var timebase: CMTimebase?
        guard CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr, let timebase else {
            throw BridgeError.unavailable
        }
        display.controlTimebase = timebase
        CMTimebaseSetTime(timebase, time: .zero)
        CMTimebaseSetRate(timebase, rate: 1)
        try enqueueStandbyFrame(on: display)
        return .init(sampleBufferDisplayLayer: display, playbackDelegate: self)
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        paused = !playing
        if let timebase = display.controlTimebase { CMTimebaseSetRate(timebase, rate: playing ? 1 : 0) }
        controller.invalidatePlaybackState()
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { paused }
    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize size: CMVideoDimensions) {}
    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval interval: CMTime, completion: @escaping () -> Void) { completion() }
    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ controller: AVPictureInPictureController) -> Bool { true }
}

@MainActor
struct StandbyProbeView: View {
    @StateObject private var probe = StandbyProbe()
    var body: some View {
        NavigationStack {
            Form {
                Text(probe.pausedRecorder ? "Three seconds of foreground recording, then paused. No idle recording requested." :
                    (probe.realAudio ? "Real microphone experiment. Fixed test speech only." : "Synthetic text only; no microphone capture."))
                Text(probe.phase).accessibilityIdentifier("probe.status")
                Text(String(probe.backgroundTicks)).accessibilityIdentifier("probe.background_ticks")
                Text(String(format: "%.2f", probe.backgroundMaxGap)).accessibilityIdentifier("probe.background_gap")
                Text(String(format: "%.2f", probe.backgroundSeconds)).accessibilityIdentifier("probe.background_seconds")
                Text(probe.resumedPiP).accessibilityIdentifier("probe.resumed_pip")
                ProbeSource(view: probe.source).frame(height: 60)
                Button("Prepare plain background") { Task { await probe.prepare(withPiP: false) } }
                    .disabled(probe.phase == "ready" || probe.phase == "active" || probe.phase == "session-only")
                    .accessibilityIdentifier("probe.plain")
                Button(probe.audioControl ? "Activate mixing audio only" :
                        (probe.sampleBuffer ? "Prepare sample-buffer PiP" : "Prepare video-call PiP")) { Task { await probe.prepare(withPiP: true) } }
                    .disabled(probe.phase == "ready" || probe.phase == "active" || probe.phase == "session-only")
                    .accessibilityIdentifier("probe.pip")
                Button("Stop experiment") { Task { await probe.stop() } }
                    .accessibilityIdentifier("probe.stop")
            }.navigationTitle("Standby experiment")
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--standby-cleanup") {
                        await probe.stop(); StandbyJournal.erase()
                    } else if ProcessInfo.processInfo.arguments.contains("--standby-autostart") {
                        await probe.prepare(withPiP: false)
                    } else if ProcessInfo.processInfo.arguments.contains("--standby-autostart-pip") {
                        await probe.prepare(withPiP: true)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    probe.enteredBackground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    probe.returningForeground()
                }
        }
    }
}
