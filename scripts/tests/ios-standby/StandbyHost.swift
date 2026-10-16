import SwiftUI
import AVKit
import OSLog

@main
@MainActor
struct StandbyHostApp: App {
    var body: some Scene { WindowGroup { StandbyHostView() } }
}

@MainActor
final class StandbyVideo: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let layer = AVPlayerLayer()
    private var pip: AVPictureInPictureController?
    private var activationID: UUID?
    @Published var phase = "ready"
    @Published var probePhase = "unknown"
    @Published var probeCommand = "none"
    @Published var probeVoice = "unknown"
    @Published var position = 0.0
    @Published var rate: Float = 0
    private let log = Logger(subsystem: "com.ichendev.utter.standbyhost", category: "StandbyVideo")

    override init() {
        super.init()
        let player = AVPlayer(url: Bundle.main.url(forResource: "probe", withExtension: "mp4")!)
        player.preventsDisplaySleepDuringVideoPlayback = false
        layer.player = player
        layer.videoGravity = .resizeAspect
    }

    func start() async {
        guard activationID == nil, phase != "stopping" else { return }
        let id = UUID()
        activationID = id
        do {
            log.notice("External video supported=\(AVPictureInPictureController.isPictureInPictureSupported())")
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                activationID = nil
                phase = "unsupported"
                return
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            pip = AVPictureInPictureController(playerLayer: layer)
            pip?.delegate = self
            layer.player?.play()
            for _ in 0..<50 {
                guard activationID == id else { return }
                if pip?.isPictureInPicturePossible == true { pip?.startPictureInPicture(); return }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard activationID == id else { return }
            stop()
            phase = "unavailable"
            log.notice("External video PiP unavailable")
        } catch {
            guard activationID == id else { return }
            stop(); phase = "failed"
        }
    }

    func stop() {
        activationID = nil
        let needsStop = pip?.isPictureInPictureActive == true || pip?.isPictureInPictureSuspended == true
        if needsStop { pip?.stopPictureInPicture() }
        layer.player?.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = needsStop ? "stopping" : "stopped"
    }

    func observeProbe() async {
        // A real third-party host has no access to Utter's private bridge group.
        #if targetEnvironment(simulator)
        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ichendev.utter.ios")
        #else
        let group: URL? = nil
        #endif
        let deadline = Date().addingTimeInterval(600)
        while !Task.isCancelled, Date() < deadline {
            position = layer.player?.currentTime().seconds ?? 0
            rate = layer.player?.rate ?? 0
            if let group, let data = try? Data(contentsOf: group.appendingPathComponent("Library/standby-probe.json")),
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let time = value["time"] as? Double {
                probePhase = Date().timeIntervalSince1970 - time > 5 ? "stale" :
                    (value["suspended"] as? Bool == true ? "suspended" : (value["active"] as? Bool == true ? "active" : "inactive"))
                probeCommand = value["command"] as? String ?? "unknown"
                probeVoice = value["voice"] as? String ?? "unknown"
            }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        }
        stop()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard pip === controller, activationID != nil else { controller.stopPictureInPicture(); return }
        phase = "active"
        log.notice("External video PiP started")
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        guard pip === controller else { return }
        stop()
        phase = "stopped"
        log.notice("External video PiP stopped")
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard pip === controller else { return }
        stop(); phase = "failed"
        log.notice("External video PiP failed to start")
    }
}

@MainActor
private struct StandbyHostView: View {
    @StateObject private var video = StandbyVideo()
    @State private var text = ""
    var body: some View {
        VStack(spacing: 16) {
            Text("External native test host")
            TextField("Fixed test text", text: $text).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("host.field")
            VideoSource(layer: video.layer).frame(height: 150)
            Text(video.phase).accessibilityIdentifier("host.video_status")
            Text(video.probePhase).accessibilityIdentifier("host.probe_status")
            Text(video.probeCommand).accessibilityIdentifier("host.probe_command")
            Text(video.probeVoice).accessibilityIdentifier("host.probe_voice")
            Text(String(format: "%.2f", video.position)).accessibilityIdentifier("host.video_position")
            Text(String(format: "%.2f", video.rate)).accessibilityIdentifier("host.video_rate")
            Button("Start video PiP") { Task { await video.start() } }
                .accessibilityIdentifier("host.video")
            Button("Stop video") { video.stop() }.accessibilityIdentifier("host.stop")
        }.padding(24).task { await video.observeProbe() }
    }
}

@MainActor
private struct VideoSource: UIViewRepresentable {
    let layer: AVPlayerLayer
    func makeUIView(context: Context) -> PlayerView { PlayerView(layer: layer) }
    func updateUIView(_ uiView: PlayerView, context: Context) {}
}

@MainActor
private final class PlayerView: UIView {
    let playerLayer: AVPlayerLayer
    init(layer: AVPlayerLayer) { playerLayer = layer; super.init(frame: .zero); self.layer.addSublayer(layer) }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layoutSubviews() { super.layoutSubviews(); playerLayer.frame = bounds }
}
