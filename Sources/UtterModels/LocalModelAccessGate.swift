import Foundation
import UtterContracts

package actor LocalModelAccessGate: ModelResourceAccess {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    @TaskLocal private static var heldGates: Set<UUID> = []
    private let identity = UUID()
    private var isOccupied = false
    private var waiters: [Waiter] = []
    package private(set) var isClosed = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    package init() {}

    package nonisolated func withAccess<Value>(_ operation: () async throws -> Value) async throws -> Value {
        if Self.heldGates.contains(identity) { return try await operation() }
        try await acquire()
        do {
            let value = try await Self.$heldGates.withValue(Self.heldGates.union([identity])) {
                try Task.checkCancellation()
                return try await operation()
            }
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }

    package var waitingTaskCount: Int { waiters.count }

    package func acquire() async throws {
        try Task.checkCancellation()
        guard !isClosed else { throw ModelResourceError.closed }
        guard isOccupied else {
            isOccupied = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        }, onCancel: {
            Task { await self.cancelWaiter(id: id) }
        })
    }

    package func release() {
        guard !waiters.isEmpty else {
            isOccupied = false
            let continuations = drainWaiters
            drainWaiters.removeAll()
            for continuation in continuations { continuation.resume() }
            return
        }
        waiters.removeFirst().continuation.resume()
    }

    package func close() async {
        isClosed = true
        let queued = waiters
        waiters.removeAll()
        for waiter in queued { waiter.continuation.resume(throwing: ModelResourceError.closed) }
        guard isOccupied else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
