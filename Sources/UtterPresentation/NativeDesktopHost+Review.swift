import AppKit
import UtterContracts
import UtterPresentationContracts

@MainActor
extension NativeDesktopHost {
    func showOverlay() {
        if state.offersRestore, state.selectionEditRestoration?.operationID == restoreDismissed { hideOverlay(); return }
        overlay?.show(context: context, targetApp: NSWorkspace.shared.frontmostApplication)
        overlayVisible = overlay != nil
        updateShortcuts()
    }

    func hideOverlay() {
        overlayVisible = false
        overlay?.hide()
        updateShortcuts()
    }

    /// Close only hides the panel; session, receipt and host text are untouched.
    func dismissOverlay() {
        if state.offersRestore { restoreDismissed = state.selectionEditRestoration?.operationID }
        restoreShown = nil
        restoreExpiry?.cancel()
        hideOverlay()
        updateShortcuts()
    }

    /// Re-read live availability from the owner on interaction or when another app activates.
    /// The owner's `isAvailable` check reads the original target through Accessibility (focused element, selection
    /// range and document value, compared against retained state) and only while focus is still on that element.
    /// This adds no extra capture, storage or input monitor; it does read host text for the integrity comparison.
    func refreshRestoration() {
        guard !closed, isCurrent(), let outputs, state.selectionEditRestoration != nil else { return }
        state.project(outputs.snapshot)
        outputsChanged()
    }

    func outputsChanged() {
        guard !closed, isCurrent() else { return }
        updateShortcuts()
        guard state.offersRestore, let restoration = state.selectionEditRestoration,
              restoration.operationID != restoreDismissed else {
            if restoreShown != nil, !state.snapshot.isBusy, !state.presentation.keepsVisible { hideOverlay() }
            restoreShown = nil
            restoreExpiry?.cancel()
            return
        }
        guard restoreShown != restoration.operationID else { return }
        restoreShown = restoration.operationID
        hideTask?.cancel()
        showOverlay()
        restoreExpiry?.cancel()
        restoreExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, restoration.expiresAt.timeIntervalSinceNow))) } catch { return }
            guard let self, !self.closed, self.restoreShown == restoration.operationID else { return }
            self.dismissOverlay()
        }
    }
}
