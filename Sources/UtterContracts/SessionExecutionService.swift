import Foundation
import UtterRuntime

package enum SessionInput: Equatable, Sendable {
    case unselected
    case local
    case remote(token: UInt64)
    case file(URL)
    case text(String)
}

package struct SessionIntent: Equatable, Sendable {
    package let id: UUID
    package let clientID: String?
    package let input: SessionInput
    package let request: InputSessionRequest
    package let mode: TextProcessingMode?
    package let operation: SessionOperation
    package init(id: UUID = UUID(), clientID: String? = nil, input: SessionInput,
                 request: InputSessionRequest = InputSessionRequest(), mode: TextProcessingMode? = nil,
                 operation: SessionOperation = .input) {
        self.id = id
        self.clientID = clientID
        self.input = input
        self.request = request
        self.mode = mode
        self.operation = operation
    }
}

package enum SessionOperation: Equatable, Sendable { case input, applyReplacement(UUID) }

package struct SessionHistoryReplacement {
    package let recordID: UUID
    package let context: InputContext?
    package let formatKind: TextFormatKind?
    package init(recordID: UUID, context: InputContext?, formatKind: TextFormatKind?) {
        self.recordID = recordID; self.context = context; self.formatKind = formatKind
    }
}

package enum SessionOutputMutation { case remember, copiedPending(UUID, message: String) }

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
    package let deliveryStatus: DeliveryStatus?
    package init(id: UUID? = nil, phase: SessionExecutionPhase? = nil, transcript: String = "",
                 text: String = "", error: String? = nil, isBusy: Bool = false, deliveryStatus: DeliveryStatus? = nil) {
        self.id = id; self.phase = phase; self.transcript = transcript
        self.text = text; self.error = error; self.isBusy = isBusy
        self.deliveryStatus = deliveryStatus
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
    package var deliveryStatus: DeliveryStatus? {
        switch self {
        case .returnedText: return nil
        case .delivery(let receipt): return receipt.status
        }
    }
    package var deliveryReason: String? {
        if case .delivery(let receipt) = self { return receipt.reason }
        return nil
    }
}

package struct SessionCompletion {
    package let transcript: String
    package let text: String
    package let acceptance: SessionAcceptance
    package var accepted: Bool { acceptance.isAccepted }
    package let record: InputRecord?
    package let followup: (any SessionFollowupWork)?
    package let historyReplacement: SessionHistoryReplacement?
    package let outputMutation: SessionOutputMutation
    package init(transcript: String, text: String, acceptance: SessionAcceptance, record: InputRecord? = nil,
                 followup: (any SessionFollowupWork)? = nil, historyReplacement: SessionHistoryReplacement? = nil,
                 outputMutation: SessionOutputMutation = .remember) {
        self.transcript = transcript; self.text = text; self.acceptance = acceptance; self.record = record
        self.followup = followup
        self.historyReplacement = historyReplacement
        self.outputMutation = outputMutation
    }
}

@MainActor
package protocol SessionFollowupWork: AnyObject {
    func install(_ completion: SessionCompletion, recordID: UUID) -> Bool
    func run() async
    func revoke()
    func close() async
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
    func bind(input: SessionInput) throws
    func attach(control: any SessionJobControl)
    func run(control: any SessionJobControl) async throws -> SessionCompletion
    func revoke()
    func close() async
}

@MainActor
package protocol SessionWorkflowFactory: AnyObject {
    /// Freeze configuration and acquire no asynchronous effects here.
    func make(_ intent: SessionIntent) throws -> any SessionJob
    func willActivate(_ intent: SessionIntent)
    /// Called inside the shared notification transaction, after execution resources drain.
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>)
}

@MainActor
package protocol SessionExecutionService: AnyObject {
    var snapshot: SessionExecutionSnapshot { get }
    func reserve(_ intent: SessionIntent) throws
    func activate(_ id: UUID, input: SessionInput?) throws
    func waitForRecording(_ id: UUID) async throws
    func waitForCompletion(_ id: UUID) async throws -> SessionExecutionSnapshot
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
    package func bind(input: SessionInput) throws { throw IntegrationError.invalidSessionState }
    package func attach(control: any SessionJobControl) {}
}

extension SessionExecutionService {
    package func activate(_ id: UUID) throws { try activate(id, input: nil) }
}

extension SessionWorkflowFactory {
    package func willActivate(_ intent: SessionIntent) {}
}
