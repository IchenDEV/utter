import Foundation
import UtterRuntime

@MainActor
package protocol InputSessionService: AnyObject {
    func createSession(_ request: InputSessionRequest, clientID: String) async throws -> InputSession
    func createSession(_ request: InputSessionRequest, input: SessionInput, clientID: String) async throws -> InputSession
    func startRecording(sessionID: UUID, clientID: String) async throws
    func stopRecording(sessionID: UUID, clientID: String) async throws -> InputSessionResult
    func disconnect(clientID: String) async
    func processAudioFile(sessionID: UUID, clientID: String, audioURL: URL) async throws -> InputSessionResult
    func beginProcessing(sessionID: UUID, clientID: String) async throws
    func completeSession(sessionID: UUID, clientID: String, finalText: String?) async throws
    func commitSession(sessionID: UUID, clientID: String, finalText: String?, record: () -> Void) throws
    func failSession(sessionID: UUID, clientID: String, error: IntegrationError) async throws
    func emitTranscriptPartial(sessionID: UUID, clientID: String, text: String) throws
    func emitTranscriptFinal(sessionID: UUID, clientID: String, text: String) throws
    func emitAudioReceived(sessionID: UUID, clientID: String) throws
    func cancel(sessionID: UUID, clientID: String) async throws
    func session(_ id: UUID, clientID: String) throws -> InputSession?
    func integrationClient(id clientID: String) -> IntegrationClient?
    func snapshotEvents(sessionID: UUID, clientID: String) throws -> [InputSessionEvent]
    func subscribeEvents(sessionID: UUID, clientID: String,
                         onEvent: @escaping @MainActor (InputSessionEvent) -> Void) throws -> (id: UUID, snapshot: [InputSessionEvent])
    func unsubscribeEvents(sessionID: UUID, subscriberID: UUID)
}

package enum SessionServices {
    package static let api = ServiceKey<any InputSessionService>("session.api")
}
