import Foundation
import AVFoundation
import UtterContracts
import UtterMediaContracts

extension VolcSpeechEngine {
    func closeConnection(_ conn: Connection) {
        let waiters = connectionLock.withLock { () -> [CheckedContinuation<Void, Never>] in
            connections.removeValue(forKey: ObjectIdentifier(conn.task))
            guard connections.isEmpty else { return [] }
            let waiters = drainWaiters
            drainWaiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resume() }
        conn.task.cancel(with: .normalClosure, reason: nil)
        conn.session.finishTasksAndInvalidate()
    }

    func sendMessage(conn: Connection, data: Data) async throws {
        do {
            try await runWithTimeout {
                try await conn.task.send(.data(data))
            }
        } catch let error as URLError where error.code == .timedOut {
            throw VolcASRError.timeout
        } catch {
            log.error("[VolcASR] send failed: \(error.localizedDescription)")
            throw error
        }
    }

    func receiveMessage(conn: Connection) async throws -> Data {
        do {
            let message = try await runWithTimeout {
                try await conn.task.receive()
            }

            switch message {
            case .data(let data):
                return data
            case .string(let text):
                log.error("[VolcASR] unexpected text frame: \(text.prefix(200))")
                throw VolcASRError.handshakeRejected
            @unknown default:
                throw VolcASRError.handshakeRejected
            }
        } catch let error as URLError where error.code == .timedOut {
            throw VolcASRError.timeout
        } catch {
            log.error("[VolcASR] receive failed: \(error.localizedDescription)")
            throw error
        }
    }

    package func runWithTimeout<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
                throw VolcASRError.timeout
            }

            guard let result = try await group.next() else {
                throw VolcASRError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
