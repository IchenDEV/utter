import Foundation
import UtterContracts

/// Keeps the voice key (F5), and every button the user has mapped, of the supported remote mapped
/// to nothing while enabled. A reconnect or wake creates a new HID service without the mapping, so
/// the controller polls for services, writes, reads back, and gives up on a service after bounded retries.
/// The set it keeps can change at runtime (`setOwnedSources`); that is a retarget, not a conflict.
@MainActor
final class RemoteKeyMappingController {
    struct Timing {
        var pollInterval: TimeInterval = 1
        /// Delay before each retry of a failed write; the total bounds the effort to about 30 s.
        var retryDelays: [TimeInterval] = [1, 2, 2, 3, 3, 4, 5, 5, 5]
        /// How long `waitingForService` is reported after a remote is expected or lost.
        var waitingGrace: TimeInterval = 30
    }

    /// What a retarget that has not finished still has to remember: what other tools had before us
    /// and which entries of ours are on the device.
    private struct Carried {
        var original: [KeyMappingEntry]
        var applied: [KeyMappingEntry]
    }

    private enum Phase {
        case active(original: [KeyMappingEntry], applied: [KeyMappingEntry], reapplied: Bool)
        case retrying(attempts: Int, reapplied: Bool, nextAt: TimeInterval, carried: Carried?)
        case failed(carried: Carried?)
        case conflict
    }

    private let provider: any RemoteKeyServiceProviding
    private let now: () -> TimeInterval
    private let timing: Timing
    private var enabled = false
    private var desired = [RemoteKeyMappingPolicy.ours]
    private var phases: [UInt64: Phase] = [:]
    private var waitingUntil: TimeInterval = 0
    private var pollTask: Task<Void, Never>?

    private(set) var state: RemoteKeyRemapState = .off
    private(set) var reapplyCount = 0
    var onChange: ((RemoteKeyRemapState, Int) -> Void)?

    init(provider: any RemoteKeyServiceProviding, timing: Timing = Timing(),
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.provider = provider
        self.timing = timing
        self.now = now
    }

    func setEnabled(_ enable: Bool) {
        guard enable != enabled else { return }
        enabled = enable
        if enable {
            tick()
            startPolling()
        } else {
            pollTask?.cancel()
            pollTask = nil
            restoreAll()
            phases.removeAll()
            publish()
        }
    }

    /// The buttons whose native keys are silenced besides the voice key. Applied at once when enabled;
    /// a failed or conflicted service gets a fresh attempt because the user changed something.
    func setOwnedSources(_ sources: [UInt64]) {
        let next = RemoteKeyMappingPolicy.desiredEntries(owning: sources)
        guard next != desired else { return }
        desired = next
        for (id, phase) in phases {
            switch phase {
            case .retrying(_, _, _, let carried):
                phases[id] = .retrying(attempts: 0, reapplied: false, nextAt: 0, carried: carried)
            case .failed(let carried?):
                phases[id] = .retrying(attempts: 0, reapplied: false, nextAt: 0, carried: carried)
            case .failed(nil), .conflict:
                phases[id] = nil
            case .active:
                break
            }
        }
        tick()
    }

    /// A remote just became ready or was asked to reconnect: report waiting and check immediately.
    func expectRemote() {
        guard enabled else { return }
        waitingUntil = now() + timing.waitingGrace
        tick()
    }

    func verifyNow() { tick() }

    func tick() {
        guard enabled else { return }
        let live = provider.matchingServices()
        let liveIDs = Set(live.map(\.id))
        for (id, phase) in phases where !liveIDs.contains(id) {
            if case .active = phase { waitingUntil = now() + timing.waitingGrace }
            phases[id] = nil
        }
        for service in live { process(service) }
        publish()
    }

    private func startPolling() {
        pollTask?.cancel()
        let interval = timing.pollInterval
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func process(_ service: any RemoteKeyService) {
        switch phases[service.id] {
        case nil:
            attempt(service, failures: 0, reapplied: false)
        case .active(let original, let applied, let reapplied):
            if applied != desired {
                attempt(service, failures: 0, reapplied: false, carried: Carried(original: original, applied: applied))
                return
            }
            guard let current = service.mappings(), !RemoteKeyMappingPolicy.isSynced(current, with: desired) else { return }
            if reapplied {
                phases[service.id] = .conflict
            } else {
                reapplyCount += 1
                attempt(service, failures: 0, reapplied: true)
            }
        case .retrying(let attempts, let reapplied, let nextAt, let carried):
            if now() >= nextAt { attempt(service, failures: attempts, reapplied: reapplied, carried: carried) }
        case .failed, .conflict:
            break
        }
    }

    private func attempt(_ service: any RemoteKeyService, failures: Int, reapplied: Bool, carried: Carried? = nil) {
        guard let existing = service.mappings() else {
            return recordFailure(service, failures: failures, reapplied: reapplied, carried: carried)
        }
        let merged = RemoteKeyMappingPolicy.applying(
            existing: existing, desired: desired, original: carried?.original ?? [], previous: carried?.applied ?? []
        )
        if merged != existing, !service.setMappings(merged) {
            _ = service.setMappings(existing)
            return recordFailure(service, failures: failures, reapplied: reapplied, carried: carried)
        }
        guard let readBack = service.mappings(), RemoteKeyMappingPolicy.isSynced(readBack, with: desired) else {
            if merged != existing { _ = service.setMappings(existing) }
            return recordFailure(service, failures: failures, reapplied: reapplied, carried: carried)
        }
        let before = carried?.original ?? []
        let original = before + RemoteKeyMappingPolicy.snapshot(of: existing).filter { !before.contains($0) }
        phases[service.id] = .active(original: original, applied: desired, reapplied: reapplied)
    }

    private func recordFailure(_ service: any RemoteKeyService, failures: Int, reapplied: Bool, carried: Carried?) {
        let attempts = failures + 1
        if attempts > timing.retryDelays.count {
            phases[service.id] = .failed(carried: carried)
        } else {
            phases[service.id] = .retrying(
                attempts: attempts, reapplied: reapplied, nextAt: now() + timing.retryDelays[attempts - 1], carried: carried
            )
        }
    }

    /// Only a service that still has entries of ours on it, and whose before-state we know, is written.
    private func restoreAll() {
        for service in provider.matchingServices() {
            let known: Carried
            switch phases[service.id] {
            case .active(let original, let applied, _)?: known = Carried(original: original, applied: applied)
            case .retrying(_, _, _, let carried?)?, .failed(let carried?)?: known = carried
            default: continue
            }
            guard let current = service.mappings(), current.contains(where: RemoteKeyMappingPolicy.isOurs) else { continue }
            _ = service.setMappings(
                RemoteKeyMappingPolicy.restoring(original: known.original, current: current, owned: known.applied)
            )
        }
    }

    private func computedState() -> RemoteKeyRemapState {
        guard enabled else { return .off }
        if phases.isEmpty { return now() < waitingUntil ? .waitingForService : .noRemote }
        var result = RemoteKeyRemapState.active
        for phase in phases.values {
            switch phase {
            case .conflict: return .conflict
            case .failed: result = .failed
            case .retrying: if result == .active { result = .waitingForService }
            case .active: break
            }
        }
        return result
    }

    private var lastReported: (RemoteKeyRemapState, Int)?

    private func publish() {
        state = computedState()
        guard lastReported?.0 != state || lastReported?.1 != reapplyCount else { return }
        lastReported = (state, reapplyCount)
        onChange?(state, reapplyCount)
    }
}
