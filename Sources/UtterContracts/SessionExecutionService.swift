import Foundation
import UtterRuntime

package enum SessionInput: Equatable, Sendable {
    case local
    case remote(token: UInt64)
    case file(URL)
}

package struct SessionIntent: Equatable, Sendable {
    package let id: UUID
    package let clientID: String?
    package let input: SessionInput
    package let request: InputSessionRequest
    package let mode: TextProcessingMode?
    package init(id: UUID = UUID(), clientID: String? = nil, input: SessionInput,
                 request: InputSessionRequest = InputSessionRequest(), mode: TextProcessingMode? = nil) {
        self.id = id
        self.clientID = clientID
        self.input = input
        self.request = request
        self.mode = mode
    }
}

package enum SessionExecutionPhase: Equatable, Sendable {
    case created, preparing, recording, transcribing, processing, delivering, completed, cancelled, failed
}

package struct SessionExecutionSnapshot: Equatable, Sendable {
    package let id: UUID?
    package let phase: SessionExecutionPhase?
    package let transcript: String
    package let text: String
    package let error: String?
    package let isBusy: Bool
    package init(id: UUID? = nil, phase: SessionExecutionPhase? = nil, transcript: String = "",
                 text: String = "", error: String? = nil, isBusy: Bool = false) {
        self.id = id; self.phase = phase; self.transcript = transcript
        self.text = text; self.error = error; self.isBusy = isBusy
    }
}

package enum SessionAcceptance {
    case returnedText
    case delivery(DeliveryReceipt)
    package var isAccepted: Bool {
        switch self {
        case .returnedText: return true
        case .delivery(let receipt): return receipt.disposition == .accepted
        }
    }
}

package struct SessionCompletion {
    package let transcript: String
    package let text: String
    package let acceptance: SessionAcceptance
    package var accepted: Bool { acceptance.isAccepted }
    package let record: InputRecord?
    package init(transcript: String, text: String, acceptance: SessionAcceptance, record: InputRecord? = nil) {
        self.transcript = transcript; self.text = text; self.acceptance = acceptance; self.record = record
    }
}

@MainActor
package protocol SessionJobControl: AnyObject {
    var isCurrent: Bool { get }
    func update(phase: SessionExecutionPhase, transcript: String)
    func cancel()
    func waitForStop() async throws
}

@MainActor
package protocol SessionJob: AnyObject {
    func attach(control: any SessionJobControl)
    func run(control: any SessionJobControl) async throws -> SessionCompletion
    func revoke()
    func close() async
}

@MainActor
package protocol SessionWorkflowFactory: AnyObject {
    /// Freeze configuration and acquire no asynchronous effects here.
    func make(_ intent: SessionIntent) throws -> any SessionJob
    /// Called inside the shared notification transaction, after execution resources drain.
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>)
}

@MainActor
package protocol SessionExecutionService: AnyObject {
    var snapshot: SessionExecutionSnapshot { get }
    func reserve(_ intent: SessionIntent) throws
    func activate(_ id: UUID) throws
    func waitForRecording(_ id: UUID) async throws
    func start(_ intent: SessionIntent) throws
    func stop() async
    func cancel()
    func observe(_ callback: @escaping (SessionExecutionSnapshot) -> Void) -> UUID
    func removeObserver(_ id: UUID)
    func observeProgress(_ callback: @escaping (SessionIntent, SessionExecutionSnapshot) -> Void) -> UUID
    func removeProgressObserver(_ id: UUID)
    func observeSettlement(_ callback: @escaping (SessionIntent, Result<SessionCompletion, Error>) -> Void) -> UUID
    func removeSettlementObserver(_ id: UUID)
}

extension SessionServices {
    package static let workflows = ServiceKey<any SessionWorkflowFactory>("session.workflows")
    package static let execution = ServiceKey<any SessionExecutionService>("session.execution")
}

extension SessionJob {
    package func attach(control: any SessionJobControl) {}
}
