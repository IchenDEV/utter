import AVKit
import SwiftUI
import UIKit
import OSLog
import UtterMobile
import UtterKeyboardBridge

/// Keeps the main app serving keyboard commands in the background through a hidden video-call Picture in Picture.
/// The system allows one PiP at a time, so another app's PiP replaces this one; that is reported, never fought.
@MainActor
final class StandbyService: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    enum Phase: String, Equatable { case off, starting, active, unsupported, failed
        var name: String { rawValue }
    }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var diagnostic = ""
    private var events: [String] = []
    let sourceView = UIView()
    private let controller: MobileController
    private let content = AVPictureInPictureVideoCallViewController()
    private var pip: AVPictureInPictureController?
    private var serving: Task<Void, Never>?
    private var activationID: UUID?
    private var stopping = false
    private let log = Logger(subsystem: "com.ichendev.utter.ios", category: "Standby")

    init(controller: MobileController) { self.controller = controller }

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    private var sceneState: String {
        guard let scene = sourceView.window?.windowScene else { return "none" }
        switch scene.activationState {
        case .foregroundActive: return "foregroundActive"
        case .foregroundInactive: return "foregroundInactive"
        case .background: return "background"
        case .unattached: return "unattached"
        @unknown default: return "unknown"
        }
    }

    private var sceneIsActive: Bool { sourceView.window?.windowScene?.activationState == .foregroundActive }

    func activate() async {
        guard activationID == nil, phase != .active, !stopping else { return }
        guard isSupported else { phase = .unsupported; await controller.enable(); return }
        let id = UUID()
        activationID = id
        phase = .starting
        await controller.enable()
        guard activationID == id else { return }
        guard controller.isEnabled else { diagnostic = "voice-off"; await fail(id); return }
        #if DEBUG
        // Control for background experiments: identical serving loop and heartbeat, but no Picture in Picture.
        if ProcessInfo.processInfo.arguments.contains("--standby-control") {
            phase = .active
            self.controller.setStandby(true)
            serving = Task { [weak self] in await self?.serve(generation: id) }
            return
        }
        #endif
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
            content.preferredContentSize = CGSize(width: 300, height: 100)
            content.view.backgroundColor = .clear
            content.view.isOpaque = false
            try prepareNeutralFrame(in: content)
            let current = AVPictureInPictureController(contentSource: .init(activeVideoCallSourceView: sourceView,
                                                                           contentViewController: content))
            current.delegate = self
            pip = current
            // A controller asked to start immediately after creation reports possible, then silently drops the request.
            try await Task.sleep(for: .milliseconds(300))
            // A start request is dropped unless the content source's scene is foreground-active;
            // a keyboard link can arrive while that transition is still in flight.
            for _ in 0..<150 {
                guard activationID == id else { return }
                if current.isPictureInPicturePossible, sceneIsActive {
                    current.startPictureInPicture()
                    await watchStart(of: current, id: id)
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            diagnostic = "never_possible;scene=\(sceneState)"
            await fail(id)
        } catch {
            diagnostic = "ex=\(String(describing: error))"
            await fail(id)
        }
    }

    /// The system reports start or failure through the delegate; silence means the request was dropped.
    private func watchStart(of current: AVPictureInPictureController, id: UUID) async {
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(100))
            guard activationID == id, phase == .starting else { return }
        }
        let state = UIApplication.shared.applicationState.rawValue
        diagnostic = "silent;win=\(sourceView.window != nil);size=\(Int(sourceView.bounds.width))x\(Int(sourceView.bounds.height));"
            + "hidden=\(sourceView.isHidden);active=\(current.isPictureInPictureActive);app=\(state);"
            + "possible=\(current.isPictureInPicturePossible);susp=\(current.isPictureInPictureSuspended);"
            + "other=\(AVAudioSession.sharedInstance().isOtherAudioPlaying);cat=\(AVAudioSession.sharedInstance().category.rawValue);"
            + "ev=\(events.joined(separator: ","))"
        log.error("PiP start gave no callback: \(self.diagnostic, privacy: .public)")
        await fail(id)
    }

    func deactivate() async {
        activationID = nil
        await shutdown()
        await controller.disable()
        phase = .off
    }

    private func fail(_ id: UUID) async {
        guard activationID == id else { return }
        activationID = nil
        await shutdown()
        await controller.disable()
        phase = .failed
    }

    private func shutdown() async {
        guard !stopping else { return }
        stopping = true
        defer { stopping = false }
        serving?.cancel(); serving = nil
        let current = pip
        current?.stopPictureInPicture()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        for _ in 0..<50 {
            if current?.isPictureInPictureActive != true && current?.isPictureInPictureSuspended != true { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        pip = nil
    }

    private func serve(generation id: UUID) async {
        var handled = Set<UUID>()
        var beat = Date.distantPast
        while !Task.isCancelled, activationID == id {
            if Date().timeIntervalSince(beat) >= 5 {
                beat = Date(); controller.beat()
                #if DEBUG
                recordHeartbeat()
                #endif
            }
            if let ids = try? controller.bridge?.pendingCommandIDs() {
                for command in ids where !handled.contains(command) {
                    handled.insert(command)
                    do { try await VoiceHost.shared.perform(command) }
                    catch { log.error("Keyboard command rejected: \(String(describing: error), privacy: .public)") }
                }
                if handled.count > 256 { handled = handled.filter { ids.contains($0) } }
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }

    #if DEBUG
    /// Lets debugger-free device experiments see whether the serving loop kept running in the background.
    private func recordHeartbeat() {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let row: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "time": Date().timeIntervalSince1970,
                                  "appState": UIApplication.shared.applicationState.rawValue,
                                  "pipActive": pip?.isPictureInPictureActive ?? false]
        if let data = try? JSONSerialization.data(withJSONObject: row) {
            try? data.write(to: library.appendingPathComponent("standby-heartbeat.json"), options: .atomic)
        }
    }
    #endif

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in events.append("willStart") }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in events.append("willStop") }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            events.append("didStart")
            guard pip === controller, let id = activationID else { controller.stopPictureInPicture(); return }
            content.preferredContentSize = CGSize(width: 300, height: 0.1)
            // The audio session was only needed to start PiP; releasing it keeps other apps' audio untouched.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            phase = .active
            self.controller.setStandby(true)
            serving = Task { [weak self] in await self?.serve(generation: id) }
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            events.append("didStop")
            guard pip === controller, !stopping else { return }
            log.notice("PiP replaced or closed by the system")
            await deactivate()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            guard pip === controller, let id = activationID else { return }
            log.error("PiP failed: \(String(describing: error), privacy: .public)")
            diagnostic = "pip-error=\(String(describing: error))"
            await fail(id)
        }
    }
}

@MainActor
struct StandbySource: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A single neutral frame; nothing is recorded or shown.
@MainActor
private func prepareNeutralFrame(in content: AVPictureInPictureVideoCallViewController) throws {
    let video = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
    let display = AVSampleBufferDisplayLayer()
    display.frame = video.bounds
    video.layer.addSublayer(display)
    content.view.subviews.forEach { $0.removeFromSuperview() }
    content.view.addSubview(video)
    var pixel: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                              [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess,
          let pixel else { throw BridgeError.unavailable }
    CVPixelBufferLockBaseAddress(pixel, [])
    if let address = CVPixelBufferGetBaseAddress(pixel) { memset(address, 0x80, CVPixelBufferGetDataSize(pixel)) }
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
