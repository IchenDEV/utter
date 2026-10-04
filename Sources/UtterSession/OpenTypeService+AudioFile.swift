import Foundation
import UtterContracts

extension OpenTypeService {
    package func processAudioFile(sessionID: UUID, clientID: String, audioURL: URL) async throws -> InputSessionResult {
        try requireAuthorized(clientID: clientID, capability: .record)
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard let session = sessions[sessionID] else { throw IntegrationError.sessionNotFound }
        guard session.state == .created, let execution else { throw IntegrationError.invalidSessionState }
        try execution.activate(sessionID, input: .file(audioURL))
        let result: SessionExecutionSnapshot
        do { result = try await execution.waitForCompletion(sessionID) }
        catch is CancellationError {
            execution.cancel(sessionID)
            await Task { await execution.stop(sessionID) }.value
            throw CancellationError()
        }
        guard let completed = sessions[sessionID], completed.state == .completed else {
            throw IntegrationError.invalidSessionState
        }
        return InputSessionResult(session: completed, transcript: result.transcript, text: result.text)
    }
}
