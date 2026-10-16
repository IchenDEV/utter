#if os(iOS)
import Foundation
import UtterContracts
import UtterKeyboardBridge

extension MobileController {
    func beginSelection(_ command: VoiceCommand) throws {
        do {
            guard let bridge, let target = command.selectionTarget, target.isValid(at: Date()),
                  target.documentID == command.lease.documentID, polishAvailable else { throw MobileError.localUnavailable }
            let selection = MobileSelectionRequest(sessionID: command.id, lease: command.lease,
                operation: .edit(target, modelID: polishModel), bridge: bridge, polisher: polishService)
            try begin(id: command.id, lease: command.lease, selection: selection)
        } catch {
            if !status.isBusy {
                status.selectionMode = true; status.requestID = command.id; status.leaseID = command.lease.id
                status.documentID = command.lease.documentID; status.phase = .failed; status.text = ""
                status.errorKey = error as? MobileError == .localUnavailable ? "ios.selection.model_unavailable" : "ios.selection.failure"
                publish()
            }
            throw error
        }
    }

    func applySelection(_ command: VoiceCommand) throws {
        guard status.selectionMode == true, status.leaseID == command.lease.id,
              status.documentID == command.lease.documentID, let session = status.requestID,
              let proposal = command.proposalID, execution?.snapshot.selectionEditProposal?.id == proposal,
              execution?.applySelectionEdit(sessionID: session, proposalID: proposal) == true else { throw BridgeError.invalidTarget }
    }

    func beginRestoration(_ command: VoiceCommand) throws {
        guard let bridge, let restoration = try bridge.selectionRestoration(), restoration.isValid(at: Date()),
              restoration.operationID == command.restoreOperationID,
              restoration.lease.generation == status.generation, restoration.lease.documentID == command.lease.documentID else { throw BridgeError.invalidTarget }
        let selection = MobileSelectionRequest(sessionID: command.id, lease: command.lease,
            operation: .restore(restoration), bridge: bridge, polisher: polishService)
        try begin(id: command.id, lease: command.lease, selection: selection)
    }

    func projectSelection(_ snapshot: SessionExecutionSnapshot) {
        status.text = ""; status.polished = nil; status.polish = nil; status.expiresAt = nil
        switch snapshot.phase {
        case .created, .preparing: status.phase = .preparing
        case .recording: status.phase = .recording
        case .transcribing, .processing, .delivering: status.phase = .processing
        case .completed:
            status.phase = .ready
            if snapshot.deliveryStatus != .inserted { status.errorKey = "ios.selection.uncertain" }
        case .cancelled: status.phase = .cancelled; status.errorKey = "ios.selection.cancelled"
        case .failed: status.phase = .failed; status.errorKey = "ios.selection.failure"
        case nil: return
        }
        if !status.isBusy { watchdog?.cancel(); watchdog = nil }
        publish()
        if let proposal = snapshot.selectionEditProposal, let selection = factory?.selectionRequest,
           selection.sessionID == proposal.sessionID, case .edit(let target, _) = selection.operation {
            let review = KeyboardSelectionReview(id: proposal.id, sessionID: proposal.sessionID, lease: selection.lease,
                target: target, recognizedInstruction: proposal.recognizedInstruction, candidate: proposal.candidate, expiresAt: proposal.expiresAt)
            do { try bridge?.publishSelectionReview(review) }
            catch { execution?.cancel(proposal.sessionID); status.errorKey = "ios.selection.failure" }
        }
    }
}
#endif
