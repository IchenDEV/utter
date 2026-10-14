import Foundation

package struct SessionPresentation: Equatable, Sendable {
    package enum Status: Equatable, Sendable {
        case idle, preparing, recording, transcribing, processing, delivering, inserted, copied, uncertain, failed
    }
    package let status: Status
    package let message: String
    package let canCopy: Bool
    private let isReviewing: Bool
    package var keepsVisible: Bool { isReviewing || status == .failed || status == .uncertain }

    package init(_ snapshot: SessionExecutionSnapshot) {
        isReviewing = snapshot.selectionEditProposal != nil || snapshot.remoteDisclosure != nil
        canCopy = !snapshot.isBusy && !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch snapshot.phase {
        case .created, .preparing:
            status = .preparing
            message = L(snapshot.remoteDisclosure == nil ? "pipeline.preparing_capture" : "selection_edit.remote_disclosure_required")
        case .recording: status = .recording; message = L("pipeline.recording")
        case .transcribing: status = .transcribing; message = L("pipeline.transcribing")
        case .processing: status = .processing; message = L(isReviewing ? "selection_edit.review" : "pipeline.formatting")
        case .delivering: status = .delivering; message = L("pipeline.inserting")
        case .completed where snapshot.deliveryStatus == .inserted: status = .inserted; message = L("status.done")
        case .completed where snapshot.deliveryStatus == .copied: status = .copied; message = L("delivery.copied")
        case .completed where snapshot.deliveryStatus == nil: status = .idle; message = L("status.ready")
        case .failed where snapshot.deliveryStatus == .uncertain:
            status = .uncertain; message = snapshot.error ?? L("delivery.uncertain")
        case .failed, .completed:
            status = .failed; message = snapshot.error ?? L("delivery.notDelivered")
        case .cancelled, .none: status = .idle; message = L("status.ready")
        }
    }
}
