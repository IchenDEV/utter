import Foundation
import UtterContracts
@testable import UtterRemoteMic

@MainActor
final class FakePressSource: RemotePressSourcing {
    var onEdge: ((RemoteButton, Bool) -> Void)?
    var onDevicesChanged: (() -> Void)?
    var status: PressSourceStatus = .live
    /// What the system answers once it has been asked.
    var statusAfterPrompt: PressSourceStatus?
    var onStop: (() -> Void)?
    private(set) var refreshes: [Bool] = []
    private(set) var stops = 0

    func refresh(prompt: Bool) -> PressSourceStatus {
        refreshes.append(prompt)
        if prompt, let statusAfterPrompt { status = statusAfterPrompt }
        return status
    }

    func stop() {
        stops += 1
        onStop?()
    }

    func press(_ button: RemoteButton) { onEdge?(button, true) }
    func release(_ button: RemoteButton) { onEdge?(button, false) }
}

/// The coordinator over the real key mapping controller and a fake device, so every write is visible.
@MainActor
final class CoordinatorRig {
    let service = FakeKeyService(id: 1)
    let provider = FakeKeyProvider()
    let clock = FakeClock()
    let source = FakePressSource()
    let controller: RemoteKeyMappingController
    private(set) var coordinator: RemoteButtonMappingCoordinator!
    private(set) var commands: [ButtonCommand] = []
    private(set) var states: [RemoteButtonMappingState] = []
    private(set) var wakes: [(delay: TimeInterval, fire: @MainActor () -> Void)] = []

    init() {
        provider.services = [service]
        controller = RemoteKeyMappingController(provider: provider, now: { [clock] in clock.time })
        coordinator = RemoteButtonMappingCoordinator(
            source: source, keys: controller, now: { [clock] in clock.time },
            scheduleWake: { [unowned self] delay, fire in
                wakes.append((delay, fire))
                return nil
            }
        )
        controller.onChange = { [unowned self] _, _ in coordinator.keyRemapChanged() }
        coordinator.onCommand = { [unowned self] in commands.append($0) }
        coordinator.onStateChange = { [unowned self] in states.append($0) }
    }

    func start(profile: RemoteButtonProfile = RemoteButtonProfile(), prompt: Bool = false) {
        controller.setEnabled(true)
        coordinator.setProfile(profile)
        coordinator.setEnabled(true, prompt: prompt)
    }

    func stop() {
        coordinator.setEnabled(false)
        controller.setEnabled(false)
    }

    /// Runs the most recent wake-up the coordinator asked for, after moving the clock to it.
    func fireWake() {
        guard let wake = wakes.last else { return }
        clock.advance(wake.delay)
        wake.fire()
    }
}

extension RemoteButtonProfile {
    static func binding(_ entries: [(RemoteButton, ButtonTrigger, ButtonAction)]) -> RemoteButtonProfile {
        var profile = RemoteButtonProfile()
        for (button, trigger, action) in entries { profile.set(action, for: trigger, of: button) }
        return profile
    }
}
