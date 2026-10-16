import Foundation
import UtterContracts

@MainActor
package final class SessionOutputState: SessionOutputStateService {
    private let notifications: StateNotifications
    private var closed = false
    private var consumedSelectionEdits: Set<UUID> = []
    private var selectionExpiry: Task<Void, Never>?
    private var pending: DeferredReplacement?
    private var observers: [UUID: (SessionOutputSnapshot) -> Void] = [:]
    package private(set) var recent: RecentSessionOutput?
    package private(set) var pendingAnchor: (any OutputAnchor)?
    package var snapshot: SessionOutputSnapshot {
        let restoration = recent?.selectionEdit.map { edit in
            SelectionEditRestoration(operationID: edit.operationID, originalSelection: edit.originalSelection,
                replacement: edit.replacement, expiresAt: edit.anchor.expiresAt,
                isAvailable: edit.anchor.isCurrent && edit.anchor.target.isCurrent
                    && !consumedSelectionEdits.contains(edit.operationID))
        }
        return SessionOutputSnapshot(recentText: recent?.text ?? "", pending: pending,
            selectionEditRestoration: restoration)
    }

    package init(notifications: StateNotifications) { self.notifications = notifications }

    package func remember(_ completion: SessionCompletion, recordID: UUID) {
        guard !closed, completion.accepted, case .delivery(let receipt) = completion.acceptance else { return }
        guard !consumedSelectionEdits.contains(receipt.operationID) else { return }
        if let edit = receipt.selectionEdit {
            guard edit.operationID == receipt.operationID, edit.replacement == completion.text, edit.replacement == edit.anchor.text,
                  edit.anchor === receipt.anchor, !edit.originalSelection.isEmpty,
                  edit.anchor.expiresAt > Date() else { return }
        }
        selectionExpiry?.cancel(); selectionExpiry = nil
        recent = completion.text.isEmpty ? nil : RecentSessionOutput(recordID: recordID, text: completion.text,
            anchor: receipt.anchor, selectionEdit: receipt.selectionEdit)
        pending = nil
        pendingAnchor = nil
        if let edit = receipt.selectionEdit {
            let operationID = edit.operationID
            let delay = max(0, edit.anchor.expiresAt.timeIntervalSinceNow)
            selectionExpiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                self?.expireSelectionEdit(operationID)
            }
        }
        notify()
    }

    @discardableResult
    package func consumeSelectionEdit(_ operationID: UUID) -> Bool {
        guard !closed, let current = recent, let edit = current.selectionEdit, edit.operationID == operationID,
              edit.anchor === current.anchor, edit.replacement == current.text,
              edit.replacement == edit.anchor.text, edit.anchor.isCurrent, edit.anchor.target.isCurrent,
              !consumedSelectionEdits.contains(operationID) else { return false }
        consumedSelectionEdits.insert(operationID)
        clearSelectionEdit(operationID)
        return true
    }

    func expireSelectionEdit(_ operationID: UUID) {
        guard !closed, recent?.selectionEdit?.operationID == operationID else { return }
        consumedSelectionEdits.insert(operationID)
        clearSelectionEdit(operationID)
    }

    private func clearSelectionEdit(_ operationID: UUID) {
        guard recent?.selectionEdit?.operationID == operationID else { return }
        selectionExpiry?.cancel(); selectionExpiry = nil
        recent = nil
        pending = nil
        pendingAnchor = nil
        notify()
    }

    @discardableResult
    package func installPending(_ replacement: DeferredReplacement, anchor: (any OutputAnchor)?) -> Bool {
        guard !closed, recent?.recordID == replacement.historyRecordID,
              recent?.text == replacement.insertedText else { return false }
        if let anchor {
            guard let recentAnchor = recent?.anchor, recentAnchor === anchor,
                  anchor.text == replacement.insertedText else { return false }
        } else if recent?.anchor != nil { return false }
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
    package func close() {
        closed = true; selectionExpiry?.cancel(); selectionExpiry = nil
        consumedSelectionEdits.removeAll(); observers.removeAll(); recent = nil; pending = nil; pendingAnchor = nil
    }

    private func notify() {
        let value = snapshot
        for id in observers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            notifications.enqueue { [weak self] in self?.observers[id]?(value) }
        }
    }
}
