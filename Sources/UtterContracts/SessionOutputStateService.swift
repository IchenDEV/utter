import Foundation
import UtterRuntime

@MainActor
package struct RecentSessionOutput {
    package let recordID: UUID
    package let text: String
    package let anchor: (any OutputAnchor)?
    package init(recordID: UUID, text: String, anchor: (any OutputAnchor)?) {
        self.recordID = recordID; self.text = text; self.anchor = anchor
    }
}

package struct SessionOutputSnapshot: Equatable {
    package let recentText: String
    package let pending: DeferredReplacement?
    package init(recentText: String = "", pending: DeferredReplacement? = nil) {
        self.recentText = recentText; self.pending = pending
    }
}

@MainActor
package protocol SessionOutputStateService: AnyObject {
    var snapshot: SessionOutputSnapshot { get }
    var recent: RecentSessionOutput? { get }
    var pendingAnchor: (any OutputAnchor)? { get }
    func remember(_ completion: SessionCompletion, recordID: UUID)
    @discardableResult func installPending(_ replacement: DeferredReplacement, anchor: any OutputAnchor) -> Bool
    @discardableResult func updatePending(_ id: UUID, mutation: (inout DeferredReplacement) -> Void) -> Bool
    func clearPending(_ id: UUID?)
    func observe(_ callback: @escaping (SessionOutputSnapshot) -> Void) -> UUID
    func removeObserver(_ id: UUID)
}

extension SessionServices {
    package static let outputs = ServiceKey<any SessionOutputStateService>("session.outputs")
}
