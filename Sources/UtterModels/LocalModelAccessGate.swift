import Foundation
import UtterContracts

package actor LocalModelAccessGate: ModelResourceAccess {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    @TaskLocal private static var heldGates: [UUID: ModelAccessLifetime] = [:]
    private let identity = UUID()
    private var isOccupied = false
    private var waiters: [Waiter] = []
    package private(set) var isClosed = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    package init() {}

    package nonisolated func withAccess<Value>(_ operation: () async throws -> Value) async throws -> Value {
        if let lifetime = Self.heldGates[identity] {
            try lifetime.begin()
            defer { lifetime.end() }
            try Task.checkCancellation()
            return try await operation()
        }
        try await acquire()
        let lifetime = ModelAccessLifetime()
        var held = Self.heldGates
        held[identity] = lifetime
        do {
            let value = try await Self.$heldGates.withValue(held) {
                try Task.checkCancellation()
                return try await operation()
            }
            await lifetime.close()
            await release()
            return value
        } catch {
            await lifetime.close()
            await release()
            throw error
        }
    }

    package nonisolated func inheritingCurrentAccess() -> any ModelResourceAccess {
        guard let lifetime = Self.heldGates[identity] else { return self }
        return BorrowedModelAccess(gate: self, identity: identity, lifetime: lifetime)
    }

    fileprivate nonisolated func withBorrowedAccess<Value>(identity: UUID, lifetime: ModelAccessLifetime,
                                                          operation: () async throws -> Value) async throws -> Value {
        guard lifetime.isOpen else { throw ModelResourceError.closed }
        var held = Self.heldGates
        held[identity] = lifetime
        return try await Self.$heldGates.withValue(held) { try await withAccess(operation) }
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

private final class ModelAccessLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true
    private var borrowers = 0
    private var waiter: CheckedContinuation<Void, Never>?
    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
    func begin() throws {
        lock.lock(); defer { lock.unlock() }
        guard open else { throw ModelResourceError.closed }
        borrowers += 1
    }
    func end() {
        lock.lock()
        borrowers -= 1
        let drained = borrowers == 0 ? waiter : nil
        if drained != nil { waiter = nil }
        lock.unlock()
        drained?.resume()
    }
    func close() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            open = false
            if borrowers == 0 {
                lock.unlock()
                continuation.resume()
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}

private struct BorrowedModelAccess: ModelResourceAccess {
    let gate: LocalModelAccessGate
    let identity: UUID
    let lifetime: ModelAccessLifetime
    func withAccess<Value>(_ operation: () async throws -> Value) async throws -> Value {
        try await gate.withBorrowedAccess(identity: identity, lifetime: lifetime, operation: operation)
    }
    func inheritingCurrentAccess() -> any ModelResourceAccess { self }
}
