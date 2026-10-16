import Foundation
import UtterContracts

extension SessionDriver {
    package func waitForRecording(_ id: UUID) async throws {
        _ = try await waitForPhase(id, recording: true)
    }
    package func waitForCompletion(_ id: UUID) async throws -> SessionExecutionSnapshot {
        try await waitForPhase(id, recording: false)
    }

    func waitForPhase(_ id: UUID, recording: Bool) async throws -> SessionExecutionSnapshot {
        guard let initial = terminalSnapshots[id] ?? (snapshot.id == id ? snapshot : nil) else {
            throw IntegrationError.invalidSessionState
        }
        let (stream, continuation) = AsyncStream<SessionExecutionSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = observe { value in
            if value.id == id { continuation.yield(value) }
        }
        defer { removeObserver(observation); continuation.finish() }
        continuation.yield(initial)
        for await value in stream {
            if Task.isCancelled { break }
            switch value.phase {
            case .completed: return value
            case .recording, .transcribing, .processing, .delivering: if recording { return value }
            case .failed: throw terminalFailures[id] ?? IntegrationError.operationFailed
            case .cancelled: throw CancellationError()
            default: continue
            }
        }
        if active?.intent.id == id {
            cancel()
            await stop()
        }
        throw CancellationError()
    }

}
