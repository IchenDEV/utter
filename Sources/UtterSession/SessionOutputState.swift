import Foundation
import UtterContracts

@MainActor
package final class SessionOutputState: SessionOutputStateService {
    private let notifications: StateNotifications
    private var closed = false
    private var pending: DeferredReplacement?
    private var observers: [UUID: (SessionOutputSnapshot) -> Void] = [:]
    package private(set) var recent: RecentSessionOutput?
    package private(set) var pendingAnchor: (any OutputAnchor)?
    package var snapshot: SessionOutputSnapshot { SessionOutputSnapshot(recentText: recent?.text ?? "", pending: pending) }

    package init(notifications: StateNotifications) { self.notifications = notifications }

    package func remember(_ completion: SessionCompletion, recordID: UUID) {
        guard !closed, completion.accepted, case .delivery(let receipt) = completion.acceptance else { return }
        recent = completion.text.isEmpty ? nil : RecentSessionOutput(recordID: recordID, text: completion.text, anchor: receipt.anchor)
        pending = nil
        pendingAnchor = nil
        notify()
    }

    @discardableResult
    package func installPending(_ replacement: DeferredReplacement, anchor: any OutputAnchor) -> Bool {
        guard !closed, let recentAnchor = recent?.anchor, recentAnchor === anchor,
              recent?.recordID == replacement.historyRecordID,
              recent?.text == replacement.insertedText, anchor.text == replacement.insertedText else { return false }
        pending = replacement
        pendingAnchor = anchor
        notify()
        return true
    }

    @discardableResult
    package func updatePending(_ id: UUID, mutation: (inout DeferredReplacement) -> Void) -> Bool {
        guard !closed, var current = pending, current.id == id else { return false }
        mutation(&current)
        pending = current
        notify()
        return true
    }

    package func clearPending(_ id: UUID?) {
        guard !closed, id == nil || pending?.id == id else { return }
        pending = nil
        pendingAnchor = nil
        notify()
    }

    package func observe(_ callback: @escaping (SessionOutputSnapshot) -> Void) -> UUID {
        let id = UUID()
        if !closed { observers[id] = callback }
        return id
    }
    package func removeObserver(_ id: UUID) { observers[id] = nil }
    package func close() { closed = true; observers.removeAll(); recent = nil; pending = nil; pendingAnchor = nil }

    private func notify() {
        let value = snapshot
        for id in observers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            notifications.enqueue { [weak self] in self?.observers[id]?(value) }
        }
    }
}
