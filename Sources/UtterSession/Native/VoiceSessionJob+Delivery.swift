import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    func unverifiedTranslation(_ result: ProcessingResult, transcript: String, text: String,
                               context: InputContext) -> SessionCompletion? {
        guard case .translation(let targetLanguage) = mode,
              result.decision.translation?.confirms(targetLanguage) != true else { return nil }
        let wrong = result.decision.translation?.target == targetLanguage
            && result.decision.translation?.status == .wrongLanguage
        let receipt = DeliveryReceipt(operationID: intent.id, disposition: .notCommitted, effect: .none,
            reason: L(wrong ? "translation.wrong_language" : "translation.unverifiable"))
        return SessionCompletion(transcript: transcript, text: text, acceptance: .delivery(receipt),
            record: InputRecord(id: intent.id, date: Date(), rawText: transcript,
                processedText: text, wasProcessed: true, context: context, deliveryStatus: .notDelivered))
    }

    func deliver(_ command: DeliveryCommand, target: (any OutputTargetLease)?, control: any SessionJobControl) async throws -> SessionAcceptance {
        try check(control)
        let prepared = try dependencies.output.prepare(DeliveryRequest(id: intent.id, command: command, target: target,
            allowsClipboardPaste: settings.allowClipboardPaste),
            isSessionCurrent: { [weak self, weak control] in
                guard let self, let control else { return false }
                return (try? self.check(control)) != nil
            })
        delivery = prepared
        return .delivery(await prepared.commit())
    }
}
