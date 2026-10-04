import Foundation
import UtterContracts

@MainActor
package final class DeferredReplacementJob: SessionJob {
    private let replacement: DeferredReplacement
    private let anchor: (any OutputAnchor)?
    private let target: (any OutputTargetLease)?
    private let outputs: any SessionOutputStateService
    private let output: any OutputService
    private let access: any ModelResourceAccess
    private let authorize: () throws -> Void
    private let operationID: UUID
    private let allowsClipboardPaste: Bool
    private var delivery: (any PreparedDelivery)?
    private var revoked = false

    package init(id: UUID, outputs: any SessionOutputStateService, output: any OutputService,
                 access: any ModelResourceAccess, target: (any OutputTargetLease)?, operationID: UUID = UUID(),
                 allowsClipboardPaste: Bool = true,
                 authorize: @escaping () throws -> Void) throws {
        guard let replacement = outputs.snapshot.pending, replacement.id == id, replacement.hasFormattedText else {
            throw IntegrationError.invalidSessionState
        }
        self.replacement = replacement; self.outputs = outputs; self.output = output
        self.access = access; self.target = target; self.authorize = authorize
        self.operationID = operationID
        self.allowsClipboardPaste = allowsClipboardPaste
        anchor = outputs.pendingAnchor
    }

    package func run(control: any SessionJobControl) async throws -> SessionCompletion {
        try await access.withAccess {
            try check(control)
            let text = replacement.formattedText ?? ""
            let decision = DeferredReplacementPolicy.decision(for: replacement, currentBundleIdentifier: target?.context.bundleIdentifier)
            let command: DeliveryCommand
            let mutation: SessionOutputMutation
            let history: SessionHistoryReplacement?
            if decision == .replace, let anchor, anchor.isCurrent,
               target?.processIdentifier == anchor.target.processIdentifier {
                command = .replaceAnchor(text, anchor)
                history = SessionHistoryReplacement(recordID: replacement.historyRecordID,
                    context: replacement.context, formatKind: replacement.formatKind)
                mutation = .remember
            } else {
                command = .clipboard(text)
                history = nil
                mutation = .copiedPending(replacement.id, message: copyMessage(decision))
            }
            control.update(phase: .delivering, transcript: replacement.rawText)
            let prepared = try output.prepare(DeliveryRequest(id: operationID, command: command, target: target,
                allowsClipboardPaste: allowsClipboardPaste),
                isSessionCurrent: { [weak self, weak control] in
                    guard let self, let control else { return false }
                    return (try? self.check(control)) != nil
                })
            delivery = prepared
            let receipt = await prepared.commit()
            await prepared.close()
            delivery = nil
            return SessionCompletion(transcript: replacement.rawText, text: text, acceptance: .delivery(receipt),
                record: receipt.disposition == .uncertain ? InputRecord(rawText: replacement.rawText, processedText: text,
                    wasProcessed: true, context: replacement.context, formatKind: replacement.formatKind) : nil,
                historyReplacement: history, outputMutation: mutation)
        }
    }

    private func check(_ control: any SessionJobControl) throws {
        try Task.checkCancellation()
        guard !revoked, control.isCurrent, outputs.snapshot.pending?.id == replacement.id else { throw CancellationError() }
        try authorize()
    }

    private func copyMessage(_ decision: DeferredReplacementDecision) -> String {
        switch decision {
        case .copy(.expired): return L("pipeline.replacement_copied_expired")
        case .copy(.appChanged): return L("pipeline.replacement_copied_app_changed")
        case .copy(.missingTarget): return L("pipeline.replacement_copied_missing_target")
        case .copy(.notReady), .replace: return L("pipeline.replacement_copied_failed")
        }
    }

    package func revoke() { revoked = true }
    package func close() async { revoke(); await delivery?.close(); delivery = nil }
}
