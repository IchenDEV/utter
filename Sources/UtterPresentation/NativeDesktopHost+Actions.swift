import AppKit
import UtterContracts
import UtterPresentationContracts

@MainActor
extension NativeDesktopHost {
    func copy(_ text: String) {
        start(SessionIntent(input: .unselected, operation: .copy(text)))
    }
    @discardableResult
    func applySelectionEdit(sessionID: UUID, proposalID: UUID) -> Bool {
        guard !closed, isCurrent(), state.selectionEditProposal?.id == proposalID,
              state.snapshot.id == sessionID else { return false }
        return execution?.applySelectionEdit(sessionID: sessionID, proposalID: proposalID) ?? false
    }
    func cancelSelectionEdit(sessionID: UUID, proposalID: UUID) {
        guard !closed, isCurrent(), state.selectionEditProposal?.id == proposalID,
              state.snapshot.id == sessionID else { return }
        execution?.cancel(sessionID)
    }
    @discardableResult
    func restoreSelectionEdit(operationID: UUID) -> Bool {
        guard !closed, isCurrent(), let execution else { return false }
        if let outputs { state.project(outputs.snapshot) }
        guard state.offersRestore, let restoration = state.selectionEditRestoration,
              restoration.operationID == operationID, Date() < restoration.expiresAt else { return false }
        do {
            try execution.start(SessionIntent(input: .text(""), operation: .restoreSelectionEdit(operationID: operationID)))
            return true
        } catch {
            diagnostics.error("Desktop restore could not start: \(error.localizedDescription)")
            return false
        }
    }
    /// The owner re-checks the retained intent, live target and expiry; a false result starts nothing.
    func authorizeRemoteDisclosure(_ intentID: UUID) -> Bool {
        guard !closed, isCurrent(), let execution, state.remoteDisclosure != nil, state.snapshot.id == intentID else { return false }
        do { try execution.authorizeRemoteDisclosure(intentID); return true }
        catch {
            diagnostics.error("Remote selection disclosure could not continue: \(error.localizedDescription)")
            return false
        }
    }
    func declineRemoteDisclosure(_ intentID: UUID) {
        guard !closed, isCurrent(), state.remoteDisclosure != nil, state.snapshot.id == intentID else { return }
        execution?.declineRemoteDisclosure(intentID)
    }
    func applyReplacement() {
        guard let pending = outputs?.snapshot.pending else { return }
        start(SessionIntent(input: .unselected, operation: .applyReplacement(pending.id)))
    }
    private func start(_ intent: SessionIntent) {
        guard !closed, isCurrent(), let execution else { return }
        do { try execution.start(intent) }
        catch { diagnostics.error("Desktop action could not start: \(error.localizedDescription)") }
    }
    func cancel() {
        guard !closed, isCurrent(), let id = state.snapshot.id else { return }
        execution?.cancel(id)
    }
    func stop() {
        guard !closed, isCurrent(), let execution, let id = state.snapshot.id else { return }
        execution.requestStop(id, at: .nanoseconds(Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)))
        Task { await execution.stop(id) }
    }
    func recover() {
        guard !closed, isCurrent(), let recovery = state.snapshot.recoveryAction else { return }
        if recovery == .models { state.selectedSettingsID = "presentation.models"; openSettings(); return }
        let anchor: String
        switch recovery {
        case .models: return
        case .microphonePrivacy: anchor = "Privacy_Microphone"
        case .accessibilityPrivacy: anchor = "Privacy_Accessibility"
        case .screenPrivacy: anchor = "Privacy_ScreenCapture"
        case .speechPrivacy: anchor = "Privacy_SpeechRecognition"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
            NSWorkspace.shared.open(url)
        }
    }
}
