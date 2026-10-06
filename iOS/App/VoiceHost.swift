import Foundation
import Combine
import ActivityKit
import UtterMobile
import UtterKeyboardBridge
#if DEBUG && targetEnvironment(simulator)
import OSLog
#endif

@MainActor
final class VoiceHost {
    static let shared = VoiceHost()
    let controller = MobileController(bridge: try? voiceBridge())
    lazy var standby = StandbyService(controller: controller)
    private var activity: Activity<VoiceActivity>?
    private var observation: AnyCancellable?
    private var activityTask: Task<Void, Never>?
    private var activityMonitor: Task<Void, Never>?
    private var starting = false

    private init() {
        let orphaned = Activity<VoiceActivity>.activities
        Task { for previous in orphaned { await previous.end(nil, dismissalPolicy: .immediate) } }
        observation = controller.$status.sink { [weak self] status in
            self?.activityTask?.cancel()
            self?.activityTask = Task { @MainActor [weak self] in await self?.updateActivity(status) }
        }
    }

    func perform(_ id: UUID) async throws {
        guard let bridge = controller.bridge, let status = try bridge.status() else { throw BridgeError.unavailable }
        // Inspect before taking; the controller owns single-use command admission.
        let command: VoiceCommand = try bridge.command(id)
        guard status.generation == command.lease.generation else { throw BridgeError.invalidTarget }
        if command.action == .start {
            guard !starting, !controller.status.isBusy else { throw BridgeError.invalidTarget }
            starting = true
        }
        defer { if command.action == .start { starting = false } }
        if command.action == .start {
            await endActivity()
            try beginActivity(id)
        }
        do { try await controller.perform(id) }
        catch {
            if command.action == .start { await endActivity() }
            throw error
        }
    }

    func startLocally() async throws {
        guard !starting, !controller.status.isBusy else { throw BridgeError.invalidTarget }
        starting = true
        defer { starting = false }
        await endActivity()
        let id = UUID()
        try beginActivity(id)
        do { try controller.beginLocal(id: id) }
        catch { await endActivity(); throw error }
    }

    private func beginActivity(_ id: UUID) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw BridgeError.unavailable }
        activity = try Activity.request(attributes: VoiceActivity(requestID: id),
                                        content: ActivityContent(state: .init(phase: VoicePhase.preparing.rawValue), staleDate: nil), pushType: nil)
        guard let current = activity else { throw BridgeError.unavailable }
        activityMonitor = Task { [weak self] in
            for await state in current.activityStateUpdates {
                guard !Task.isCancelled else { return }
                if state == .ended || state == .dismissed {
                    if let self, self.controller.status.requestID == id, self.controller.status.isBusy {
                        await self.controller.cancel()
                    }
                    return
                }
            }
        }
    }

    private func updateActivity(_ status: VoiceStatus) async {
        guard !Task.isCancelled else { return }
        guard let activity, activity.attributes.requestID == status.requestID else { return }
        if status.isBusy {
            await activity.update(ActivityContent(state: .init(phase: status.phase.rawValue), staleDate: Date().addingTimeInterval(125)))
        } else { await endActivity() }
    }

    private func endActivity() async {
        guard let ending = activity else { return }
        activity = nil
        activityMonitor?.cancel(); activityMonitor = nil
        await ending.end(nil, dismissalPolicy: .immediate)
    }

    #if DEBUG && targetEnvironment(simulator)
    func runSimulatorBridge() async {
        guard ProcessInfo.processInfo.arguments.contains("--bridge-diagnostic"),
              ProcessInfo.processInfo.arguments.contains("--simulator-bridge-host") else { return }
        // This foreground test host bypasses system intent dispatch; it cannot prove background wake-up.
        var handled = Set<UUID>()
        var delayedCancel: (Date, VoiceCommand)?
        var injectedDelay = false
        var lastBeat = Date.distantPast
        let deadline = Date().addingTimeInterval(600)
        while !Task.isCancelled, Date() < deadline, handled.count < 128 {
            do {
                if controller.isEnabled, let bridge = controller.bridge {
                    if Date().timeIntervalSince(lastBeat) >= 5 { lastBeat = Date(); controller.beat() }
                    if let (delivery, command) = delayedCancel, Date() >= delivery {
                        try bridge.post(VoiceCommand(lease: command.lease, action: .cancel))
                        delayedCancel = nil
                        Logger(subsystem: "com.ichendev.utter.ios", category: "SimulatorBridge").notice("Delivered simulator delayed cancel")
                    }
                    for id in try bridge.pendingCommandIDs() where !handled.contains(id) {
                        guard !Task.isCancelled, Date() < deadline, handled.count < 128 else { return }
                        handled.insert(id)
                        let command = try? bridge.command(id)
                        try? await perform(id)
                        if !injectedDelay, let command, command.action == .cancel,
                           ProcessInfo.processInfo.arguments.contains("--simulator-delayed-cancel") {
                            injectedDelay = true
                            delayedCancel = (Date().addingTimeInterval(8), command)
                        }
                    }
                }
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }
        }
    }
    #endif
}
