import Foundation
import UtterContracts

@MainActor
package final class RestoreSelectionEditJob: SessionJob {
    private let edit: SelectionEditReceipt
    private let sessionID: UUID
    private let outputs: any SessionOutputStateService
    private let output: any OutputService
    private let authorize: () throws -> Void
    private var revoked = false
    private var delivery: (any PreparedDelivery)?

    package init(operationID: UUID, sessionID: UUID, outputs: any SessionOutputStateService,
                 output: any OutputService, authorize: @escaping () throws -> Void) throws {
        guard let recent = outputs.recent, let edit = recent.selectionEdit,
              edit.operationID == operationID, edit.anchor === recent.anchor,
              edit.replacement == recent.text, edit.replacement == edit.anchor.text,
              !edit.originalSelection.isEmpty, edit.anchor.isCurrent, edit.anchor.target.isCurrent else {
            throw DeliveryError.invalidTarget
        }
        self.edit = edit; self.sessionID = sessionID
        self.outputs = outputs; self.output = output; self.authorize = authorize
    }

    package func run(control: any SessionJobControl) async throws -> SessionCompletion {
        try check(control)
        guard edit.anchor.isCurrent, edit.anchor.target.isCurrent,
              outputs.consumeSelectionEdit(edit.operationID) else { throw DeliveryError.invalidTarget }
        // Consume before preparing any effect. An uncertain restoration cannot be retried.
        control.update(phase: .delivering, transcript: "")
        let prepared = try output.prepare(DeliveryRequest(id: sessionID,
            command: .replaceAnchor(edit.originalSelection, edit.anchor), target: edit.anchor.target,
            allowsClipboardPaste: false), isSessionCurrent: { [weak self, weak control] in
                guard let self, let control else { return false }
                return (try? self.check(control)) != nil
            })
        delivery = prepared
        let receipt = await prepared.commit()
        await prepared.close()
        delivery = nil
        return SessionCompletion(transcript: "", text: edit.originalSelection, acceptance: .delivery(receipt), outputMutation: .preserve)
    }

    private func check(_ control: any SessionJobControl) throws {
        try Task.checkCancellation()
        guard !revoked, control.isCurrent else { throw CancellationError() }
        try authorize()
    }

    package func revoke() { revoked = true }
    package func close() async { revoke(); await delivery?.close(); delivery = nil }
}
