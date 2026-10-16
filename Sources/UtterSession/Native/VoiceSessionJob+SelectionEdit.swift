import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    func selectedOutputMutation(_ acceptance: SessionAcceptance) -> SessionOutputMutation {
        guard case .delivery(let receipt) = acceptance, receipt.selectionEdit != nil else { return .preserve }
        return .remember
    }

    func prepareSelectionEdit(_ candidate: String, instruction: String, target: (any OutputTargetLease)?,
                             control: any SessionJobControl) async throws {
        try check(control)
        guard let target, target.isCurrent, let original = target.selectedText, !original.isEmpty,
              !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalidTarget }
        await recording?.stopCapture()
        await callbacks.drain()
        engine?.cancelListening()
        await engine?.drainRecognition()
        await recording?.close()
        recording = nil; engine = nil
        try check(control)
        guard target.isCurrent else { throw DeliveryError.invalidTarget }
        guard target.selectedText == original, original == selectedTextAtCapture else { throw DeliveryError.invalidTarget }
        control.update(phase: .delivering, transcript: instruction)
    }
}
