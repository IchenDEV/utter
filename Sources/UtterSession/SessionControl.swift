import Foundation
import UtterContracts

@MainActor
final class SessionControl: SessionJobControl {
    private let current: () -> Bool
    private let cancelSession: () -> Void
    private let updateSnapshot: (SessionExecutionPhase, String) -> Void
    private var cancelled = false
    private var stopped = false
    private var activated = false
    private var activationWaiter: CheckedContinuation<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?
    private var stopWaiterID: UUID?

    init(isCurrent: @escaping () -> Bool, cancel: @escaping () -> Void, update: @escaping (SessionExecutionPhase, String) -> Void) {
        current = isCurrent
        cancelSession = cancel
        updateSnapshot = update
    }
    var isCurrent: Bool { !cancelled && current() }
    var isStopped: Bool { stopped }
    func update(phase: SessionExecutionPhase, transcript: String) {
        guard isCurrent else { return }
        updateSnapshot(phase, transcript)
    }
    func cancel() { if isCurrent { cancelSession() } }
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
        guard waiter == nil else { throw IntegrationError.invalidSessionState }
        let id = UUID()
        defer { if stopWaiterID == id { waiter = nil; stopWaiterID = nil } }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiter = continuation; stopWaiterID = id }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.stopWaiterID == id else { return }
                self.waiter?.resume(throwing: CancellationError())
                self.waiter = nil
                self.stopWaiterID = nil
            }
        }
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
    }
    func stop() { stopped = true; waiter?.resume(); waiter = nil; stopWaiterID = nil }
    func revoke() {
        cancelled = true
        waiter?.resume(throwing: CancellationError()); waiter = nil
        stopWaiterID = nil
        activationWaiter?.resume(throwing: CancellationError()); activationWaiter = nil
    }
}
