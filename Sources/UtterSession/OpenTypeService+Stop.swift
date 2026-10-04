import Foundation
import UtterContracts

extension OpenTypeService {
    package func stopRecording(sessionID: UUID, clientID: String) async throws -> InputSessionResult {
        try requireAuthorized(clientID: clientID, capability: .record)
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard let execution, let session = sessions[sessionID], session.state == .recording,
              execution.snapshot.id == sessionID else { throw IntegrationError.invalidSessionState }
        execution.requestStop(sessionID, at: nil)
        await execution.stop(sessionID)
        let result = try await execution.waitForCompletion(sessionID)
        guard let completed = sessions[sessionID], completed.state == .completed else {
            throw IntegrationError.invalidSessionState
        }
        return InputSessionResult(session: completed, transcript: result.transcript, text: result.text)
    }

    package func disconnect(clientID: String) async {
        guard let id = revokeSession(clientID: clientID) else { return }
        await drainSession(sessionID: id, clientID: clientID)
    }

    package func revokeSession(clientID: String) -> UUID? {
        guard let execution, let id = execution.snapshot.id, sessionOwners[id] == clientID,
              sessions[id]?.state.isTerminal == false else { return nil }
        execution.cancel(id)
        return id
    }

    package func drainSession(sessionID: UUID, clientID: String) async {
        guard sessionOwners[sessionID] == clientID else { return }
        await execution?.stop(sessionID)
    }
}
