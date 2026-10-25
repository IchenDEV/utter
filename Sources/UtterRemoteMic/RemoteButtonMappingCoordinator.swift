import Foundation
import UtterContracts

/// A recognized gesture and what the profile binds to it. The executor decides how to perform it.
package struct ButtonCommand: Equatable, Sendable {
    package var button: RemoteButton
    package var trigger: ButtonTrigger
    package var action: ButtonAction

    package init(button: RemoteButton, trigger: ButtonTrigger, action: ButtonAction) {
        self.button = button
        self.trigger = trigger
        self.action = action
    }
}

/// Joins the three parts of the button mapping and keeps one rule: **a key is silenced only while
/// its presses are observed.** The press source must be live before the key mapping controller is
/// given any button beyond the voice key; losing the source (permission, device) hands the
/// controller an empty set at once; disabling removes the silence before the observer goes away.
/// Actions are emitted only while the key mapping reports `active`, so a key whose native event is
/// not yet silenced never fires twice.
@MainActor
final class RemoteButtonMappingCoordinator {
    struct Timing {
        var pollInterval: TimeInterval = 1
        var gestures = GestureTiming()
    }

    typealias WakeScheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Task<Void, Never>?

    private let source: any RemotePressSourcing
    private let keys: RemoteKeyMappingController
    private let now: () -> TimeInterval
    private let timing: Timing
    private let scheduleWake: WakeScheduler

    private var enabled = false
    private var profile = RemoteButtonProfile()
    private var plan = ButtonMappingPlan.make(from: RemoteButtonProfile())
    private var recognizers: [RemoteButton: ButtonGestureRecognizer] = [:]
    private var sourceStatus = PressSourceStatus.stopped
    private var pollTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?

    private(set) var state = RemoteButtonMappingState.off
    var onStateChange: ((RemoteButtonMappingState) -> Void)?
    var onCommand: ((ButtonCommand) -> Void)?

    init(
        source: any RemotePressSourcing, keys: RemoteKeyMappingController, timing: Timing = Timing(),
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        scheduleWake: @escaping WakeScheduler = RemoteButtonMappingCoordinator.sleepingWake
    ) {
        self.source = source
        self.keys = keys
        self.timing = timing
        self.now = now
        self.scheduleWake = scheduleWake
    }

    /// `prompt`: the user just turned the feature on, so the system may be asked for permission.
    func setEnabled(_ enable: Bool, prompt: Bool = false) {
        guard enable != enabled else {
            if enable, prompt { evaluate(prompt: true) }
            return
        }
        enabled = enable
        if enable {
            source.onEdge = { [weak self] button, isDown in self?.handleEdge(button, isDown: isDown) }
            source.onDevicesChanged = { [weak self] in self?.evaluate() }
            evaluate(prompt: prompt)
            startPolling()
        } else {
            pollTask?.cancel()
            pollTask = nil
            wakeTask?.cancel()
            wakeTask = nil
            keys.setOwnedSources([])
            source.onEdge = nil
            source.onDevicesChanged = nil
            source.stop()
            sourceStatus = .stopped
            recognizers = [:]
            publish()
        }
    }

    func setProfile(_ new: RemoteButtonProfile) {
        guard new != profile else { return }
        profile = new
        plan = ButtonMappingPlan.make(from: new)
        evaluate()
    }

    /// The user asked for permission from the page.
    func requestPermission() { evaluate(prompt: true) }

    /// Re-checks permission and devices: on the poll, when the app becomes active, when the page opens.
    func refresh() { evaluate() }

    /// The key mapping controller's state changed (it is read from the controller, not copied).
    func keyRemapChanged() { publish() }

    // MARK: evaluation

    private func evaluate(prompt: Bool = false) {
        guard enabled else { return }
        sourceStatus = source.refresh(prompt: prompt)
        let live = sourceStatus == .live
        keys.setOwnedSources(live ? plan.sources : [])
        syncRecognizers(live: live)
        publish()
    }

    private func computeState() -> RemoteButtonMappingState {
        guard enabled else { return .off }
        switch sourceStatus {
        case .stopped, .waitingForRemote: return .waitingForRemote
        case .needsPermission(let canAsk): return .needsPermission(canAsk: canAsk)
        case .needsRestart: return .needsRestart
        case .failed: return .failed
        case .live:
            switch keys.state {
            case .active: return .active
            case .conflict: return .conflict
            case .failed: return .failed
            case .off, .noRemote, .waitingForService: return .waitingForRemote
            }
        }
    }

    private func publish() {
        let next = computeState()
        guard next != state else { return }
        state = next
        onStateChange?(next)
    }

    private func startPolling() {
        pollTask?.cancel()
        let interval = timing.pollInterval
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                self.evaluate()
            }
        }
    }

    // MARK: gestures

    /// Only buttons that are owned have a recognizer, so a press of any other key is ignored.
    /// A recognizer whose bindings did not change keeps its state across a profile edit.
    private func syncRecognizers(live: Bool) {
        guard live else {
            recognizers = [:]
            wakeTask?.cancel()
            wakeTask = nil
            return
        }
        var next: [RemoteButton: ButtonGestureRecognizer] = [:]
        for owned in plan.owned {
            if let existing = recognizers[owned.button], existing.bindings == owned.gestures {
                next[owned.button] = existing
            } else {
                next[owned.button] = ButtonGestureRecognizer(bindings: owned.gestures, timing: timing.gestures)
            }
        }
        recognizers = next
        armWake()
    }

    private func handleEdge(_ button: RemoteButton, isDown: Bool) {
        guard enabled, var recognizer = recognizers[button] else { return }
        let time = now()
        let fired = isDown ? recognizer.press(at: time) : recognizer.release(at: time)
        recognizers[button] = recognizer
        dispatch(fired, for: button)
        armWake()
    }

    private func advance() {
        let time = now()
        for button in RemoteButton.allCases {
            guard var recognizer = recognizers[button] else { continue }
            let fired = recognizer.advance(to: time)
            recognizers[button] = recognizer
            dispatch(fired, for: button)
        }
        armWake()
    }

    private func dispatch(_ fired: [GestureFiring], for button: RemoteButton) {
        guard computeState() == .active else { return }
        for firing in fired {
            let trigger: ButtonTrigger
            switch firing.gesture {
            case .single: trigger = .single
            case .double: trigger = .double
            case .long: trigger = .long
            }
            onCommand?(ButtonCommand(
                button: button, trigger: trigger, action: profile.bindings(for: button).action(for: trigger)
            ))
        }
    }

    private func armWake() {
        wakeTask?.cancel()
        wakeTask = nil
        guard let deadline = recognizers.values.compactMap(\.nextDeadline).min() else { return }
        wakeTask = scheduleWake(max(0, deadline - now())) { [weak self] in self?.advance() }
    }

    static func sleepingWake(_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            fire()
        }
    }
}
