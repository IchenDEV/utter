import UIKit
import UtterKeyboardBridge

enum SelectionInputChange { case text, selectionWill, selectionDid }

extension KeyboardController {
    func prepareSelection(id: UUID, lease: KeyboardLease) throws -> Bool {
        guard let bridge else { throw BridgeError.unavailable }
        invalidateSelection()
        let target = try KeyboardSelectionTarget(documentID: documentID(), selectedText: textDocumentProxy.selectedText,
            contextBefore: textDocumentProxy.documentContextBeforeInput, contextAfter: textDocumentProxy.documentContextAfterInput)
        try bridge.revoke(lease.id)
        let renewed = KeyboardLease(generation: lease.generation, documentID: lease.documentID)
        try bridge.renew(renewed)
        try bridge.post(VoiceCommand(id: id, lease: renewed, action: .startSelection, selectionTarget: target))
        selectionTarget = target; selectionSessionID = id
        state.lease = renewed; state.pending = true; state.errorKey = nil
        pollSelection(lease: renewed, sessionID: id)
        return true
    }

    func applySelectionEdit() {
        guard visible, hasFullAccess, !state.selectionPending, let review = state.selectionReview,
              review.isApplicable(at: Date()), review.sessionID == selectionSessionID,
              let output = selectionOutput, output.edit.phase == .review,
              output.edit.target.matches(documentID: documentID(), selectedText: textDocumentProxy.selectedText,
                contextBefore: textDocumentProxy.documentContextBeforeInput, contextAfter: textDocumentProxy.documentContextAfterInput),
              let lease = state.lease, let bridge else { invalidateSelection(); return }
        do {
            state.selectionPending = true
            try bridge.post(VoiceCommand(lease: lease, action: .applySelection, proposalID: review.id))
        } catch { invalidateSelection(); state.errorKey = "ios.selection.failure" }
    }

    func cancelSelectionEdit() {
        guard !state.selectionPending else { return }
        if let lease = state.lease { _ = prepare(id: UUID(), action: .cancel, lease: lease) }
        invalidateSelection(); invalidate(); refresh()
        state.errorKey = "ios.selection.cancelled"
    }

    func restoreSelectionEdit() {
        guard visible, hasFullAccess, !state.selectionPending,
              let restoration = state.selectionRestoration, restoration.isValid(at: Date()),
              let output = selectionOutput, output.edit.phase == .applied,
              output.edit.hasConfirmedValue(documentID: documentID(), selectedText: textDocumentProxy.selectedText,
                contextBefore: textDocumentProxy.documentContextBeforeInput, contextAfter: textDocumentProxy.documentContextAfterInput),
              var lease = state.lease, let bridge else { invalidateSelection(); return }
        do {
            guard try bridge.selectionRestoration() == restoration else { throw BridgeError.invalidTarget }
            let session = UUID()
            lease.expiresAt = Date().addingTimeInterval(5)
            try bridge.renew(lease)
            try bridge.post(VoiceCommand(id: session, lease: lease, action: .restoreSelection, restoreOperationID: restoration.operationID))
            state.lease = lease; selectionSessionID = session; selectionAwaitingSettlement = false
            state.pending = true; state.selectionPending = true
            pollSelection(lease: lease, sessionID: session)
        } catch { invalidateSelection(); state.errorKey = "ios.selection.failure" }
    }

    func pollSelection(lease: KeyboardLease, sessionID: UUID) {
        polling?.cancel()
        polling = Task { [weak self] in
            let admissionDeadline = Date().addingTimeInterval(12)
            while let self, self.visible, !Task.isCancelled {
                do {
                    guard self.hasFullAccess, let bridge = self.bridge, self.documentID() == lease.documentID,
                          let status = try bridge.status(), status.generation == lease.generation else {
                        self.endSelectionPolling(); return
                    }
                    var renewed = lease; renewed.expiresAt = Date().addingTimeInterval(5)
                    try bridge.renew(renewed); self.state.lease = renewed
                    if status.requestID != sessionID {
                        guard Date() < admissionDeadline else { self.endSelectionPolling(); self.state.errorKey = "ios.selection.failure"; return }
                    } else {
                        guard status.selectionMode == true, status.leaseID == lease.id, status.documentID == lease.documentID else {
                            self.endSelectionPolling(); return
                        }
                        self.state.status = status; self.state.pending = status.phase == .preparing
                        if !status.isBusy {
                            self.state.selectionReview = nil; self.state.selectionPending = false
                            self.selectionSessionID = nil; self.selectionTarget = nil; self.selectionExpectedCallbacks.removeAll()
                            self.selectionAwaitingSettlement = false
                            if status.errorKey != nil || self.selectionOutput?.edit.phase != .applied { self.invalidateSelection() }
                            self.state.errorKey = status.errorKey
                            self.invalidate(); self.refresh(); return
                        }
                        if self.selectionAwaitingSettlement {
                            // The native operation is consumed; only the same session's terminal state may settle it.
                        } else if let operation = try bridge.selectionOperation(sessionID: sessionID) {
                            try self.performSelectionOperation(operation)
                        } else if let review = try bridge.selectionReview(sessionID: sessionID) {
                            try self.installSelectionReview(review)
                        } else if let target = self.selectionTarget {
                            guard target.matches(documentID: self.documentID(), selectedText: self.textDocumentProxy.selectedText,
                                contextBefore: self.textDocumentProxy.documentContextBeforeInput, contextAfter: self.textDocumentProxy.documentContextAfterInput) else {
                                self.endSelectionPolling(); return
                            }
                        }
                    }
                    try await Task.sleep(for: .milliseconds(200))
                } catch is CancellationError { return }
                catch { self.endSelectionPolling(); self.state.errorKey = "ios.selection.failure"; return }
            }
        }
    }

    private func installSelectionReview(_ review: KeyboardSelectionReview) throws {
        guard let target = selectionTarget, review.sessionID == selectionSessionID, review.lease.id == state.lease?.id,
              target.createdAt == review.target.createdAt,
              target.matches(documentID: review.target.documentID, selectedText: review.target.original,
                contextBefore: review.target.before, contextAfter: review.target.after),
              review.target.matches(documentID: documentID(), selectedText: textDocumentProxy.selectedText,
                contextBefore: textDocumentProxy.documentContextBeforeInput, contextAfter: textDocumentProxy.documentContextAfterInput) else { throw BridgeError.invalidTarget }
        if let output = selectionOutput {
            guard output.edit.id == review.id else { throw BridgeError.invalidTarget }
        } else {
            selectionOutput = KeyboardSelectionOutput(edit: try KeyboardSelectionEdit(id: review.id, target: target, candidate: review.candidate))
        }
        state.selectionReview = review
    }

    private func performSelectionOperation(_ operation: KeyboardSelectionOperation) throws {
        guard let bridge, let output = selectionOutput, operation.sessionID == selectionSessionID,
              operation.lease.id == state.lease?.id, operation.lease.documentID == documentID() else { throw BridgeError.invalidTarget }
        switch operation.kind {
        case .apply: guard operation.proposalID == output.edit.id, state.selectionPending else { throw BridgeError.invalidTarget }
        case .restore: guard operation.restorationID == state.selectionRestoration?.operationID else { throw BridgeError.invalidTarget }
        }
        try bridge.takeSelectionOperation(operation)
        selectionExpectedCallbacks = [.text, .selectionWill, .selectionDid]
        var confirmed = false
        do {
            if operation.kind == .apply { confirmed = try output.apply(proxy: textDocumentProxy, documentID: { self.documentID() }) }
            else { confirmed = try output.restore(proxy: textDocumentProxy, documentID: { self.documentID() }) }
        } catch { confirmed = false }
        let acknowledgement = KeyboardSelectionAcknowledgement(operation: operation, wrote: output.wroteThisOperation, confirmed: confirmed)
        let restoration = confirmed && operation.kind == .apply
            ? KeyboardSelectionRestoration(operationID: operation.id, sessionID: operation.sessionID,
                lease: operation.lease, expiresAt: output.edit.target.expiresAt) : nil
        try bridge.acknowledgeSelection(acknowledgement, restoration: restoration)
        selectionAwaitingSettlement = true
        state.selectionReview = nil; selectionTarget = nil
        state.selectionRestoration = restoration
        if !confirmed { state.errorKey = "ios.selection.uncertain"; output.invalidate(); selectionExpectedCallbacks.removeAll() }
    }

    func observeOwnedSelectionChange(_ change: SelectionInputChange) -> Bool {
        guard let output = selectionOutput, selectionSessionID != nil else { return false }
        if output.isWriting { return true }
        guard selectionExpectedCallbacks.remove(change) != nil else { return false }
        // An expected callback is admitted once, only while the exact confirmed native value is still intact.
        return output.edit.hasConfirmedValue(documentID: documentID(), selectedText: textDocumentProxy.selectedText,
            contextBefore: textDocumentProxy.documentContextBeforeInput, contextAfter: textDocumentProxy.documentContextAfterInput)
    }

    func expireSelectionRestoration() {
        if let restoration = state.selectionRestoration, !restoration.isValid(at: Date()) { invalidateSelection() }
    }

    func invalidateSelection() {
        if let session = selectionSessionID, let lease = state.lease { try? bridge?.discardCommand(session, lease: lease) }
        if let restoration = state.selectionRestoration { try? bridge?.clearSelectionRestoration(operationID: restoration.operationID) }
        selectionOutput?.invalidate(); selectionOutput = nil; selectionTarget = nil; selectionSessionID = nil
        selectionExpectedCallbacks.removeAll()
        selectionAwaitingSettlement = false
        state.selectionReview = nil; state.selectionRestoration = nil; state.selectionPending = false
    }

    private func endSelectionPolling() {
        invalidateSelection(); invalidate(); refresh()
        state.errorKey = "ios.selection.failure"
    }
}
