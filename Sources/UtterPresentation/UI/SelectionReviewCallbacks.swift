import SwiftUI
import UtterContracts
import UtterPresentationContracts

/// A localization key (not text) so a notice follows live UI-language changes.
final class ReviewNotice: ObservableObject {
    @Published var key: String?
}

/// Every closure reaches the owner through `PresentationContext`; the owner re-validates IDs, phase and expiry.
struct SelectionReviewCallbacks {
    var apply: (SelectionEditProposal) -> Bool = { _ in false }
    var cancel: (SelectionEditProposal) -> Void = { _ in }
    var restore: (SelectionEditRestoration) -> Bool = { _ in false }
    var refresh: () -> Void = {}
    var authorize: (UUID) -> Bool = { _ in false }
    var decline: (UUID) -> Void = { _ in }
    var notice = ReviewNotice()
    static var none: SelectionReviewCallbacks { SelectionReviewCallbacks() }
}

extension SelectionReviewCallbacks {
    @MainActor
    init(context: PresentationContext, notice: ReviewNotice, onDecline: @escaping () -> Void) {
        self.init(
            apply: { context.applySelectionEdit($0.sessionID, $0.id) },
            cancel: { context.cancelSelectionEdit($0.sessionID, $0.id) },
            restore: { context.restoreSelectionEdit($0.operationID) },
            refresh: context.refreshRestoration,
            authorize: context.authorizeRemoteDisclosure,
            decline: { onDecline(); context.declineRemoteDisclosure($0) },
            notice: notice)
    }
}
