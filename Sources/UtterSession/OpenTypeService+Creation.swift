import Foundation
import UtterContracts

extension OpenTypeService {
    package func createSession(_ request: InputSessionRequest, clientID: String) async throws -> InputSession {
        try await createSession(request, input: .local, clientID: clientID)
    }

    package func createSession(_ request: InputSessionRequest, input: SessionInput, clientID: String) async throws -> InputSession {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard sessions.values.allSatisfy({ $0.state.isTerminal }) else {
            throw IntegrationError.busy
        }

        let now = Date()
        let session = InputSession(
            id: UUID(),
            request: request,
            state: .created,
            createdAt: now,
            updatedAt: now
        )
        try notifications.settle {
            try execution?.reserve(SessionIntent(id: session.id, clientID: clientID, input: input, request: request))
            sessions[session.id] = session
            sessionOwners[session.id] = clientID
            nextSequenceBySession[session.id] = 1
            appendEvent(.sessionCreated, sessionID: session.id, at: now)
            registry.markUsed(clientID: clientID, at: now)
        }

        return session
    }

}
