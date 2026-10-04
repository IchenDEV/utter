import AppKit
import UtterContracts
import UtterPresentationContracts

@MainActor
extension NativeDesktopHost {
    func copy(_ text: String) {
        start(SessionIntent(input: .unselected, operation: .copy(text)))
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
