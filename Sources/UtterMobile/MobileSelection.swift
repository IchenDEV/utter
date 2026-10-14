#if os(iOS)
import Foundation
import UtterContracts
import UtterProcessing
import UtterKeyboardBridge

enum MobileSelectionOperation {
    case edit(KeyboardSelectionTarget, modelID: String)
    case restore(KeyboardSelectionRestoration)
}

struct MobileSelectionRequest {
    let sessionID: UUID
    let lease: KeyboardLease
    let operation: MobileSelectionOperation
    let bridge: SharedVoiceBridge
    let polisher: LocalPolisher
}

extension MobileJob {
    func finishSelection(_ instruction: String, control: any SessionJobControl) async throws -> SessionCompletion {
        guard let selection, case .edit(let target, let modelID) = selection.operation,
              target.isValid(at: Date()) else { throw BridgeError.invalidTarget }
        let inputLanguage: InputLanguage = language == "en" ? .english : .chinese
        let candidate = try await SelectionEditRecipe.candidate(selectedText: target.original, intent: .custom(instruction),
            inputLanguage: inputLanguage, spokenCommand: instruction, dictionarySnapshot: dictionary) { prompt, system, options in
                try await selection.polisher.generate(prompt: prompt, system: system, options: options, modelID: modelID)
            }
        try check(control)
        let proposal = SelectionEditProposal(sessionID: selection.sessionID, targetID: target.documentID,
            originalSelection: target.original, recognizedInstruction: instruction, candidate: candidate, expiresAt: target.expiresAt)
        // Native authority checks also reject replacements spanning neighboring graphemes.
        _ = try KeyboardSelectionEdit(id: proposal.id, target: target, candidate: candidate)
        // The control publishes this proposal through the existing controller observation.
        try await control.waitForSelectionEditDecision(proposal)
        try check(control)
        guard target.isValid(at: Date()) else { throw BridgeError.expired }
        try selection.bridge.clearSelectionReview(sessionID: selection.sessionID)
        let receipt = try await deliverSelection(kind: .apply, proposalID: proposal.id, restorationID: nil, control: control)
        return SessionCompletion(transcript: "", text: "", acceptance: .delivery(receipt), outputMutation: .preserve)
    }

    func restoreSelection(control: any SessionJobControl) async throws -> SessionCompletion {
        guard let selection, case .restore(let restoration) = selection.operation,
              restoration.isValid(at: Date()), try selection.bridge.selectionRestoration() == restoration else { throw BridgeError.invalidTarget }
        control.update(phase: .delivering, transcript: "")
        // Retire the original restoration slot before a native operation can be published.
        try selection.bridge.clearSelectionRestoration(operationID: restoration.operationID)
        let receipt = try await deliverSelection(kind: .restore, proposalID: nil, restorationID: restoration.operationID, control: control)
        return SessionCompletion(transcript: "", text: "", acceptance: .delivery(receipt), outputMutation: .preserve)
    }

    private func deliverSelection(kind: KeyboardSelectionOperationKind, proposalID: UUID?, restorationID: UUID?,
                                  control: any SessionJobControl) async throws -> DeliveryReceipt {
        guard let selection, let lease = try selection.bridge.lease(selection.lease.id),
              lease.documentID == selection.lease.documentID, lease.generation == selection.lease.generation else { throw BridgeError.invalidTarget }
        let operation = KeyboardSelectionOperation(sessionID: selection.sessionID, lease: lease, kind: kind,
            proposalID: proposalID, restorationID: restorationID)
        selectionOutput = operation
        try selection.bridge.publishSelectionOperation(operation)
        while Date() < operation.expiresAt {
            try check(control)
            if let acknowledgement = try selection.bridge.selectionAcknowledgement(for: operation) {
                return DeliveryReceipt(operationID: operation.id,
                    disposition: acknowledgement.confirmed ? .accepted : .uncertain,
                    effect: acknowledgement.wrote ? .keyboardInsertion : .none,
                    reason: acknowledgement.confirmed ? nil : "ios.selection.uncertain",
                    confirmation: acknowledgement.confirmed ? .targetValue : .none)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Publication permits a native effect; missing acknowledgement cannot prove that none occurred.
        return DeliveryReceipt(operationID: operation.id, disposition: .uncertain,
            effect: .keyboardInsertion, reason: "ios.selection.uncertain")
    }

    func clearSelectionPayload() {
        guard let selection else { return }
        try? selection.bridge.clearSelectionReview(sessionID: selection.sessionID)
        if let selectionOutput { try? selection.bridge.clearSelectionOperation(selectionOutput) }
        selectionOutput = nil
    }
}
#endif
