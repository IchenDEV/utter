#if DEBUG
import SwiftUI
import AVKit
import OSLog
import UtterMobile
import UtterKeyboardBridge

@main
@MainActor
struct StandbyProbeApp: App {
    var body: some Scene { WindowGroup { StandbyProbeView() } }
}

@MainActor
final class StandbyProbe: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let controller = VoiceHost.shared.controller
    let realAudio = ProcessInfo.processInfo.arguments.contains("--standby-real-audio")
    let noAudioSession = ProcessInfo.processInfo.arguments.contains("--standby-no-audio")
    let audioControl = ProcessInfo.processInfo.arguments.contains("--standby-audio-control")
    let sampleBuffer = ProcessInfo.processInfo.arguments.contains("--standby-sample-buffer")
    let sessionOnly = ProcessInfo.processInfo.arguments.contains("--standby-session-only")
    let recordCategory = ProcessInfo.processInfo.arguments.contains("--standby-record-category")
    let pausedRecorder = ProcessInfo.processInfo.arguments.contains("--standby-paused-recorder")
    private let recorder = StandbyPausedRecorder()
    private var sessionActivationSucceeded = false
    private let sampleSource = StandbySampleSource()
    let source = UIView()
    private let content = AVPictureInPictureVideoCallViewController()
    private let log = Logger(subsystem: "com.ichendev.utter.ios", category: "StandbyProbe")
    private var pip: AVPictureInPictureController?
    private var loop: Task<Void, Never>?
    private var commands: [UUID: Task<Void, Never>] = [:]
    private var activationID: UUID?
    private var stopping = false
    private let journal = StandbyJournal()
    @Published var phase = "disabled"
    @Published var backgroundTicks = 0
    @Published var backgroundMaxGap = 0.0
    @Published var backgroundSeconds = 0.0
    @Published var resumedPiP = "unknown"
    @Published var commandOutcome = "none"
    private var backgroundStart: TimeInterval?
    private var lastBackgroundTick: TimeInterval?

    func prepare(withPiP: Bool) async {
        guard !Task.isCancelled, activationID == nil, pip == nil, !stopping else { return }
        let id = UUID()
        activationID = id
        journal.reset()
        backgroundTicks = 0; backgroundMaxGap = 0; lastBackgroundTick = nil
        backgroundStart = nil; backgroundSeconds = 0; resumedPiP = "unknown"
        do {
            if withPiP, !AVPictureInPictureController.isPictureInPictureSupported() {
                activationID = nil
                phase = "unsupported"
                log.notice("PiP supported=false sourceWindow=\(self.source.window != nil) width=\(self.source.bounds.width) height=\(self.source.bounds.height)")
                report()
                return
            }
            if realAudio {
                await controller.enable()
                guard controller.isEnabled else { throw BridgeError.unavailable }
            } else { try await controller.enableBridgeDiagnostic(text: "Utter bridge sample") }
            guard activationID == id else { return }
            phase = "ready"
            loop = Task { [weak self] in await self?.serve() }
            if sessionOnly {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(recordCategory ? .playAndRecord : .playback, options: .mixWithOthers)
                try session.setActive(true)
                sessionActivationSucceeded = true
                if pausedRecorder {
                    try await recorder.prepareAndPause()
                    guard activationID == id else { return }
                }
                phase = "session-only"
                report()
                return
            }
            guard withPiP else { return }
            log.notice("PiP supported=\(AVPictureInPictureController.isPictureInPictureSupported()) sourceWindow=\(self.source.window != nil) width=\(self.source.bounds.width) height=\(self.source.bounds.height)")
            if !noAudioSession {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
                try AVAudioSession.sharedInstance().setActive(true)
            }
            if audioControl { phase = "audio-control"; report(); return }
            content.preferredContentSize = CGSize(width: 300, height: 100)
            content.view.backgroundColor = .clear
            content.view.isOpaque = false
            if sampleBuffer {
                pip = AVPictureInPictureController(contentSource: try sampleSource.prepare(in: source))
            } else {
                try prepareStandbyFrame(in: content)
                pip = AVPictureInPictureController(contentSource: .init(activeVideoCallSourceView: source,
                                                                       contentViewController: content))
            }
            pip?.delegate = self
            try await Task.sleep(for: .milliseconds(100))
            for _ in 0..<50 {
                guard activationID == id else { return }
                if pip?.isPictureInPicturePossible == true {
                    phase = "starting"
                    pip?.startPictureInPicture()
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            await stop()
            phase = "unavailable"
            report()
            log.notice("PiP unavailable")
        } catch {
            guard activationID == id else { return }
            await stop()
            phase = "failed"
            report()
            log.error("Prepare failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func serve() async {
        let deadline = Date().addingTimeInterval(600)
        var handled = Set<UUID>()
        var heartbeat = Date.distantPast
        while !Task.isCancelled, Date() < deadline, handled.count < 128 {
            do {
                if UIApplication.shared.applicationState == .background, backgroundStart != nil {
                    let now = ProcessInfo.processInfo.systemUptime
                    if let previous = lastBackgroundTick {
                        backgroundMaxGap = max(backgroundMaxGap, now - previous)
                    }
                    lastBackgroundTick = now
                    backgroundTicks += 1
                }
                if Date().timeIntervalSince(heartbeat) >= 10 {
                    heartbeat = Date()
                    log.notice("Heartbeat state=\(UIApplication.shared.applicationState.rawValue) pip=\(self.pip?.isPictureInPictureActive == true) idleDisabled=\(UIApplication.shared.isIdleTimerDisabled)")
                }
                report()
                if let bridge = controller.bridge {
                    for id in try pendingCommands() where !handled.contains(id) {
                        guard !Task.isCancelled else { return }
                        guard Date() < deadline, handled.count < 128 else { Task { await stop() }; return }
                        handled.insert(id)
                        let command = try bridge.command(id)
                        log.notice("Command \(command.action.rawValue, privacy: .public) state=\(UIApplication.shared.applicationState.rawValue) pip=\(self.pip?.isPictureInPictureActive == true)")
                        let generation = activationID
                        commands[id] = Task { [weak self] in
                            guard let self, !Task.isCancelled, self.activationID == generation else { return }
                            defer { self.commands[id] = nil }
                            do {
                                if self.realAudio { try await VoiceHost.shared.perform(id) }
                                else { try await self.controller.perform(id) }
                                guard self.activationID == generation else { return }
                                self.commandOutcome = "accepted-\(command.action.rawValue)"
                            } catch {
                                guard self.activationID == generation else { return }
                                let failure = error as NSError
                                self.commandOutcome = "rejected-\(command.action.rawValue)-\(failure.domain)-\(failure.code)"
                                self.log.error("Command rejected: \(self.commandOutcome, privacy: .public)")
                            }
                        }
                    }
                }
                try await Task.sleep(for: .milliseconds(250))
            } catch { break }
        }
        if !Task.isCancelled { Task { await stop() } }
    }

    func enteredBackground() {
        if recorder.isRecording {
            let id = activationID
            recorder.stop()
            Task { guard activationID == id else { return }; await stop(); phase = "failed"; report() }
            return
        }
        guard activationID != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        backgroundStart = now; lastBackgroundTick = now
        backgroundTicks = 0; backgroundMaxGap = 0; backgroundSeconds = 0
    }

    func returningForeground() {
        guard let start = backgroundStart, let last = lastBackgroundTick else { return }
        let now = ProcessInfo.processInfo.systemUptime
        backgroundMaxGap = max(backgroundMaxGap, now - last)
        backgroundSeconds = now - start
        backgroundStart = nil; lastBackgroundTick = nil
        resumedPiP = pip?.isPictureInPictureSuspended == true ? "suspended" :
            (pip?.isPictureInPictureActive == true ? "active" : "inactive")
    }
    private func pendingCommands() throws -> [UUID] {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ichendev.utter.ios") else {
            throw BridgeError.unavailable
        }
        return try FileManager.default.contentsOfDirectory(at: group.appendingPathComponent("UtterVoice-v1"),
                                                           includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("command-") && $0.pathExtension == "json" }
            .prefix(64)
            .compactMap { UUID(uuidString: String($0.deletingPathExtension().lastPathComponent.dropFirst(8))) }
    }

    func stop() async {
        guard !stopping else { return }
        stopping = true
        defer { stopping = false }
        activationID = nil
        loop?.cancel(); loop = nil
        commands.values.forEach { $0.cancel() }; commands.removeAll()
        recorder.stop()
        let current = pip
        report(event: "stop-requested")
        current?.stopPictureInPicture()
        await controller.disable()
        var audioStopped = true
        do {
            if !noAudioSession || sessionActivationSucceeded {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                sessionActivationSucceeded = false
            }
        }
        catch {
            audioStopped = false
            log.error("Stop audio deactivation failed: \(String(describing: error), privacy: .public)")
        }
        for _ in 0..<50 {
            if current?.isPictureInPictureActive != true && current?.isPictureInPictureSuspended != true { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        let stopped = current?.isPictureInPictureActive != true && current?.isPictureInPictureSuspended != true
        if stopped { pip = nil; sampleSource.reset() }
        phase = stopped && audioStopped ? "disabled" : "failed"
        log.notice("Stop confirmed=\(stopped) audioDeactivated=\(audioStopped)")
        report()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard pip === controller, activationID != nil else { controller.stopPictureInPicture(); return }
        phase = "active"
        if !sampleBuffer { content.preferredContentSize = CGSize(width: 300, height: 0.1) }
        do {
            if !noAudioSession { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            log.notice("PiP started, sampleBuffer=\(self.sampleBuffer), noAudioSession=\(self.noAudioSession)")
        } catch {
            log.error("PiP audio deactivation failed: \(String(describing: error), privacy: .public)")
            Task { await stop(); phase = "failed"; report() }
            return
        }
        report()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        guard pip === controller else { return }
        log.notice("PiP stopped state=\(UIApplication.shared.applicationState.rawValue)")
        report(event: "did-stop-before-cleanup")
        guard !stopping else { return }
        Task {
            guard pip === controller, !stopping else { return }
            await stop()
            if phase == "disabled" { phase = "stopped" }
            report()
        }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        log.error("PiP failed: \(String(describing: error), privacy: .public)")
        guard pip === controller else { return }
        Task {
            guard pip === controller else { return }
            await stop(); phase = "failed"; report()
        }
    }
    private func report(event: String = "sample") {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ichendev.utter.ios") else { return }
        let value: [String: Any] = ["event": event, "stopping": stopping,
                                   "pid": ProcessInfo.processInfo.processIdentifier,
                                   "sessionOnly": sessionOnly, "recordCategory": recordCategory,
                                   "pausedRecorder": pausedRecorder, "recorderRecording": recorder.isRecording,
                                   "recorderPrepared": recorder.isPrepared, "recorderTime": recorder.currentTime,
                                   "sessionActivationSucceeded": sessionActivationSucceeded,
                                   "audioCategory": AVAudioSession.sharedInstance().category.rawValue,
                                   "backgroundTicks": backgroundTicks, "backgroundMaxGap": backgroundMaxGap,
                                   "backgroundSeconds": backgroundSeconds,
                                   "noAudioSession": noAudioSession, "audioControl": audioControl, "sampleBuffer": sampleBuffer,
                                   "active": pip?.isPictureInPictureActive == true,
                                   "suspended": pip?.isPictureInPictureSuspended == true,
                                   "phase": phase, "command": commandOutcome,
                                   "voice": controller.status.phase.rawValue,
                                   "appState": UIApplication.shared.applicationState.rawValue,
                                   "idleDisabled": UIApplication.shared.isIdleTimerDisabled,
                                   "engineRunning": MobileCaptureDiagnostics.engineRunning,
                                   "sessionDeactivated": MobileCaptureDiagnostics.sessionDeactivated,
                                   "completedFrames": MobileCaptureDiagnostics.completedFrames,
                                   "time": Date().timeIntervalSince1970]
        journal.write(value, group: group)
    }
}
#endif
