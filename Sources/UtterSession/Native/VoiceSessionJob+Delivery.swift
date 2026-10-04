import Foundation
import UtterContracts

extension VoiceSessionJob {
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
