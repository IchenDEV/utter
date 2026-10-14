import Foundation
import UtterContracts

extension SessionDriver {
    func hasTemporarySelectionContent(_ intent: SessionIntent) -> Bool {
        if active?.control.hasSelectionEditReview == true { return true }
        if case .selectionEdit = intent.mode { return true }
        if case .restoreSelectionEdit = intent.operation { return true }
        return false
    }

    func terminal(for result: Result<SessionCompletion, Error>) -> SessionPerformance.Terminal {
        switch result {
        case .failure(let error): return error is CancellationError ? .cancelled : .failed
        case .success(let completion):
            switch completion.acceptance.deliveryStatus {
            case .inserted: return .inserted
            case .copied: return .copied
            case .uncertain: return .uncertain
            case .notDelivered: return .notDelivered
            case .none: return completion.accepted ? .returnedText : .failed
            }
        }
    }
}
