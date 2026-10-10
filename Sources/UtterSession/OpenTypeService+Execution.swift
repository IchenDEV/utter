import Foundation
import UtterContracts

extension OpenTypeService {
    func projectExecution(_ intent: SessionIntent, snapshot: SessionExecutionSnapshot) {
        guard sessionOwners[intent.id] == intent.clientID,
              var session = sessions[intent.id], !session.state.isTerminal else { return }
        let now = Date()
        switch snapshot.phase {
        case .recording:
            if session.state != .recording {
                session.state = .recording
                session.updatedAt = now
                sessions[intent.id] = session
                appendEvent(.recordingStarted, sessionID: intent.id, at: now)
            }
            if !snapshot.transcript.isEmpty,
               eventsBySession[intent.id]?.last(where: { $0.type == .transcriptPartial })?.text != snapshot.transcript {
                appendEvent(.transcriptPartial, sessionID: intent.id, at: now, text: snapshot.transcript)
            }
        case .transcribing:
            if !hasEvent(.audioReceived, sessionID: intent.id) {
                appendEvent(.audioReceived, sessionID: intent.id, at: now)
            }
        case .processing, .delivering:
            if !snapshot.transcript.isEmpty, !hasEvent(.transcriptFinal, sessionID: intent.id) {
                appendEvent(.transcriptFinal, sessionID: intent.id, at: now, text: snapshot.transcript)
            }
            if session.state != .processing {
                session.state = .processing
                session.updatedAt = now
                sessions[intent.id] = session
                appendEvent(.processingStarted, sessionID: intent.id, at: now)
            }
        default: break
        }
    }

    private func hasEvent(_ type: InputSessionEvent.EventType, sessionID: UUID) -> Bool {
        eventsBySession[sessionID]?.contains(where: { $0.type == type }) == true
    }

    func settleExecution(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {
        guard sessionOwners[intent.id] == intent.clientID,
              var session = sessions[intent.id], !session.state.isTerminal else { return }
        let now = Date()
        session.updatedAt = now
        switch result {
        case .success(let completion) where completion.accepted:
            session.state = .completed
            sessions[intent.id] = session
            if !completion.transcript.isEmpty, !hasEvent(.transcriptFinal, sessionID: intent.id) {
                appendEvent(.transcriptFinal, sessionID: intent.id, at: now, text: completion.transcript)
            }
            appendEvent(.textFinal, sessionID: intent.id, at: now, text: completion.text)
            appendEvent(.sessionCompleted, sessionID: intent.id, at: now)
        case .success:
            session.state = .failed
            sessions[intent.id] = session
            appendEvent(.sessionFailed, sessionID: intent.id, at: now, error: IntegrationError.operationFailed.payload)
        case .failure(let error):
            let cancelled = error is CancellationError
            session.state = cancelled ? .cancelled : .failed
            sessions[intent.id] = session
            appendEvent(cancelled ? .sessionCancelled : .sessionFailed, sessionID: intent.id, at: now,
                        error: cancelled ? nil : ((error as? IntegrationError) ?? .operationFailed).payload)
        }
    }
}
