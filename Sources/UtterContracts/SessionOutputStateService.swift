import Foundation
import UtterRuntime

@MainActor
package struct RecentSessionOutput {
    package let recordID: UUID
    package let text: String
    package let anchor: (any OutputAnchor)?
    package let selectionEdit: SelectionEditReceipt?
    package init(recordID: UUID, text: String, anchor: (any OutputAnchor)?, selectionEdit: SelectionEditReceipt? = nil) {
        self.recordID = recordID; self.text = text; self.anchor = anchor; self.selectionEdit = selectionEdit
    }
}

package struct SessionOutputSnapshot: Equatable {
    package let recentText: String
    package let pending: DeferredReplacement?
    package let selectionEditRestoration: SelectionEditRestoration?
    package init(recentText: String = "", pending: DeferredReplacement? = nil,
                 selectionEditRestoration: SelectionEditRestoration? = nil) {
        self.recentText = recentText; self.pending = pending
        self.selectionEditRestoration = selectionEditRestoration
    }
}

package struct SelectionEditRestoration: Equatable, Sendable {
    package let operationID: UUID
    package let originalSelection: String
    package let replacement: String
    package let expiresAt: Date
    package let isAvailable: Bool
    package init(operationID: UUID, originalSelection: String, replacement: String,
                 expiresAt: Date, isAvailable: Bool) {
        self.operationID = operationID; self.originalSelection = originalSelection
        self.replacement = replacement; self.expiresAt = expiresAt; self.isAvailable = isAvailable
    }
}

@MainActor
package protocol SessionOutputStateService: AnyObject {
    var snapshot: SessionOutputSnapshot { get }
    var recent: RecentSessionOutput? { get }
    var pendingAnchor: (any OutputAnchor)? { get }
    func remember(_ completion: SessionCompletion, recordID: UUID)
    @discardableResult func consumeSelectionEdit(_ operationID: UUID) -> Bool
    @discardableResult func installPending(_ replacement: DeferredReplacement, anchor: (any OutputAnchor)?) -> Bool
    @discardableResult func updatePending(_ id: UUID, mutation: (inout DeferredReplacement) -> Void) -> Bool
    func clearPending(_ id: UUID?)
    func observe(_ callback: @escaping (SessionOutputSnapshot) -> Void) -> UUID
    func removeObserver(_ id: UUID)
}

extension SessionServices {
    package static let outputs = ServiceKey<any SessionOutputStateService>("session.outputs")
}
