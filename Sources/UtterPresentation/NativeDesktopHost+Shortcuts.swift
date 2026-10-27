import Foundation
import UtterContracts

@MainActor
extension NativeDesktopHost {
    func updateShortcuts() {
        let snapshot = state.snapshot
        let canCancel = overlayVisible && !closed && isCurrent() && snapshot.isSelectionEditing && snapshot.isBusy
            && [.preparing, .recording, .transcribing, .processing].contains(snapshot.phase)
        let restore = overlayVisible && !closed && isCurrent() && state.offersRestore
            && state.selectionEditRestoration?.operationID != restoreDismissed
            ? state.selectionEditRestoration?.operationID : nil
        shortcuts.update(cancel: canCancel ? snapshot.id : nil, restore: restore)
        let cancelAvailable = snapshot.id.map { shortcuts.isRegistered(.cancel($0)) } == true
        let restoreAvailable = restore.map { shortcuts.isRegistered(.restore($0)) } == true
        if state.selectionEditCancelShortcut != cancelAvailable { state.selectionEditCancelShortcut = cancelAvailable }
        if state.selectionEditRestoreShortcut != restoreAvailable { state.selectionEditRestoreShortcut = restoreAvailable }
    }

    func handleShortcut(_ action: OverlayShortcuts.Action) {
        guard overlayVisible, !closed, isCurrent() else { return }
        switch action {
        case .cancel(let id):
            guard state.snapshot.id == id, state.snapshot.isBusy, state.snapshot.isSelectionEditing,
                  [.preparing, .recording, .transcribing, .processing].contains(state.snapshot.phase) else { return }
            execution?.cancel(id)
        case .restore(let id):
            guard id != restoreDismissed else { return }
            _ = restoreSelectionEdit(operationID: id)
        }
        updateShortcuts()
    }
}
