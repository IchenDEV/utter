import Foundation

package enum BoundedWaitOutcome {
    case finished
    case failed(any Error)
    case timedOut
}

/// Awaits `operation` for at most `limit`, then gives up on it.
///
/// A task group is not used: it returns only after every child ends, and an `await` on a
/// continuation nobody resumes ignores cancellation, so the group would hang with it.
/// The loser of the race is cancelled and abandoned instead.
package enum BoundedWait {
    package static func run(
        limit: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        operation: @escaping @MainActor () async throws -> Void
    ) async -> BoundedWaitOutcome {
        let race = Race()
        return await withCheckedContinuation { continuation in
            race.install(continuation)
            let worker = Task { @MainActor in
                do { try await operation(); race.settle(.finished) }
                catch { race.settle(.failed(error)) }
            }
            let timer = Task {
                do { try await sleep(limit) } catch { return }
                race.settle(.timedOut)
            }
            race.attach(worker: worker, timer: timer)
        }
    }
}

private final class Race: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<BoundedWaitOutcome, Never>?
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var outcome: BoundedWaitOutcome?

    func install(_ continuation: CheckedContinuation<BoundedWaitOutcome, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func attach(worker: Task<Void, Never>, timer: Task<Void, Never>) {
        let settled = lock.withLock { () -> BoundedWaitOutcome? in
            self.worker = worker
            self.timer = timer
            return outcome
        }
        if let settled { cancelLoser(of: settled, worker: worker, timer: timer) }
    }

    func settle(_ result: BoundedWaitOutcome) {
        let claimed = lock.withLock { () -> (CheckedContinuation<BoundedWaitOutcome, Never>, Task<Void, Never>?, Task<Void, Never>?)? in
            guard outcome == nil, let continuation else { return nil }
            outcome = result
            self.continuation = nil
            return (continuation, worker, timer)
        }
        guard let (continuation, worker, timer) = claimed else { return }
        if let worker, let timer { cancelLoser(of: result, worker: worker, timer: timer) }
        continuation.resume(returning: result)
    }

    private func cancelLoser(of result: BoundedWaitOutcome, worker: Task<Void, Never>, timer: Task<Void, Never>) {
        if case .timedOut = result { worker.cancel() } else { timer.cancel() }
    }
}
