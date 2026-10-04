import Foundation
import UtterContracts

@MainActor
final class SessionControl: SessionJobControl {
    private let current: () -> Bool
    private let updateSnapshot: (SessionExecutionPhase, String) -> Void
    private var cancelled = false
    private var stopped = false
    private var activated = false
    private var activationWaiter: CheckedContinuation<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?

    init(isCurrent: @escaping () -> Bool, update: @escaping (SessionExecutionPhase, String) -> Void) {
        current = isCurrent
        updateSnapshot = update
    }
    var isCurrent: Bool { !cancelled && current() }
    func update(phase: SessionExecutionPhase, transcript: String) {
        guard isCurrent else { return }
        updateSnapshot(phase, transcript)
    }
    func activate() { activated = true; activationWaiter?.resume(); activationWaiter = nil }
    func waitForActivation() async throws {
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
        if !activated { try await withCheckedThrowingContinuation { activationWaiter = $0 } }
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
    }
    func waitForStop() async throws {
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
        if stopped { return }
        try await withCheckedThrowingContinuation { waiter = $0 }
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
    }
    func stop() { stopped = true; waiter?.resume(); waiter = nil }
    func revoke() {
        cancelled = true
        waiter?.resume(throwing: CancellationError()); waiter = nil
        activationWaiter?.resume(throwing: CancellationError()); activationWaiter = nil
    }
}
