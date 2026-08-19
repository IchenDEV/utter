import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func showOverlay() {
        overlay.show(
            appState: appState,
            targetApp: recordingTargetApp,
            onCancel: { [weak self] in
                self?.cancel()
            },
            onConfirm: { [weak self] in
                Task { @MainActor in
                    await self?.stop()
                }
            }
        )
    }

    func showNoSpeechDetected(reason: String) {
        Log.info("[VoicePipeline] no speech detected: \(reason)")
        cancelScreenContextCapture()
        appState.phase = .idle
        appState.statusMessage = L("status.no_speech_detected")
        hideOverlayAfterDelay()
    }

    func resetToIdle() {
        recordingTargetApp = nil
        appState.phase = .idle
        appState.statusMessage = L("status.ready")
        overlay.hide()
    }

    func markReadyIfPossible() {
        if case .error = appState.phase { return }
        appState.statusMessage = L("status.ready")
    }

    func hideOverlayAfterDelay() {
        hideOverlayTask?.cancel()
        hideOverlayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, !appState.isRecording else { return }
            overlay.hide()
        }
    }

    func showBusyHint() {
        let saved = appState.statusMessage
        appState.statusMessage = L("pipeline.busy")
        soundPlayer.playStop()
        showOverlay()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if appState.statusMessage == L("pipeline.busy") {
                appState.statusMessage = saved
            }
        }
    }

    func showErrorHint(_ message: String) {
        appState.phase = .error(message)
        appState.statusMessage = message
        appState.resetDownloadProgress()
        soundPlayer.playStop()
        showOverlay()
        hideOverlayAfterDelay()
    }

    func showInsertionFailedAlert(text: String, reason: String) {
        let alert = NSAlert()
        alert.messageText = L("pipeline.insert_failed_title")
        alert.informativeText = L("pipeline.insert_failed_body") + reason
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("common.ok"))
        alert.icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        alert.runModal()
    }

    func userFacingErrorMessage(for error: Error) -> String {
        switch error {
        case let error as VolcASRError:
            return error.localizedDescription
        case let error as WhisperError:
            return error.localizedDescription
        case let error as AppleSpeechError:
            return error.localizedDescription
        case let error as LocalASRError:
            return error.localizedDescription
        case let error as LocalASRRuntimeError:
            return error.localizedDescription
        case is URLError:
            return L("error.network_request_failed")
        default:
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain || nsError.domain.hasPrefix("Network.") {
                return L("error.network_request_failed")
            }
            return L("error.operation_failed")
        }
    }
}
