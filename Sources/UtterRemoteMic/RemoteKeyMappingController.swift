import Foundation
import UtterContracts

/// Keeps the voice key (F5) of the supported remote mapped to nothing while enabled.
/// A reconnect or wake creates a new HID service without the mapping, so the controller
/// polls for services, writes, reads back, and gives up on a service after bounded retries.
@MainActor
final class RemoteKeyMappingController {
    struct Timing {
        var pollInterval: TimeInterval = 1
        /// Delay before each retry of a failed write; the total bounds the effort to about 30 s.
        var retryDelays: [TimeInterval] = [1, 2, 2, 3, 3, 4, 5, 5, 5]
        /// How long `waitingForService` is reported after a remote is expected or lost.
        var waitingGrace: TimeInterval = 30
    }

    private enum Phase {
        case active(original: [KeyMappingEntry], reapplied: Bool)
        case retrying(attempts: Int, reapplied: Bool, nextAt: TimeInterval)
        case failed
        case conflict
    }

    private let provider: any RemoteKeyServiceProviding
    private let now: () -> TimeInterval
    private let timing: Timing
    private var enabled = false
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
        case .active(_, let reapplied):
            guard let current = service.mappings(), !RemoteKeyMappingPolicy.containsOurs(current) else { return }
            if reapplied {
                phases[service.id] = .conflict
            } else {
                reapplyCount += 1
                attempt(service, failures: 0, reapplied: true)
            }
        case .retrying(let attempts, let reapplied, let nextAt):
            if now() >= nextAt { attempt(service, failures: attempts, reapplied: reapplied) }
        case .failed, .conflict:
            break
        }
    }

    private func attempt(_ service: any RemoteKeyService, failures: Int, reapplied: Bool) {
        guard let existing = service.mappings() else {
            return recordFailure(service, failures: failures, reapplied: reapplied)
        }
        let merged = RemoteKeyMappingPolicy.applying(existing: existing)
        if merged != existing, !service.setMappings(merged) {
            _ = service.setMappings(existing)
            return recordFailure(service, failures: failures, reapplied: reapplied)
        }
        guard let readBack = service.mappings(), RemoteKeyMappingPolicy.containsOurs(readBack) else {
            if merged != existing { _ = service.setMappings(existing) }
            return recordFailure(service, failures: failures, reapplied: reapplied)
        }
        phases[service.id] = .active(original: RemoteKeyMappingPolicy.snapshot(of: existing), reapplied: reapplied)
    }

    private func recordFailure(_ service: any RemoteKeyService, failures: Int, reapplied: Bool) {
        let attempts = failures + 1
        if attempts > timing.retryDelays.count {
            phases[service.id] = .failed
        } else {
            phases[service.id] = .retrying(
                attempts: attempts, reapplied: reapplied, nextAt: now() + timing.retryDelays[attempts - 1]
            )
        }
    }

    private func restoreAll() {
        for service in provider.matchingServices() {
            guard case .active(let original, _)? = phases[service.id],
                  let current = service.mappings(), RemoteKeyMappingPolicy.containsOurs(current) else { continue }
            _ = service.setMappings(RemoteKeyMappingPolicy.restoring(original: original, current: current))
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
