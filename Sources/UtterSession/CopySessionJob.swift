import Foundation
import UtterContracts

@MainActor
package final class CopySessionJob: SessionJob {
    private let id: UUID
    private let text: String
    private let output: any OutputService
    private var revoked = false
    private var delivery: (any PreparedDelivery)?

    package init(id: UUID, text: String, output: any OutputService) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntegrationError.invalidSessionState
        }
        self.id = id; self.text = text; self.output = output
    }

    package func run(control: any SessionJobControl) async throws -> SessionCompletion {
        try Task.checkCancellation()
        guard !revoked, control.isCurrent else { throw CancellationError() }
        control.update(phase: .delivering, transcript: "")
        let prepared = try output.prepare(DeliveryRequest(id: id, command: .clipboard(text)),
            isSessionCurrent: { [weak self, weak control] in
                self?.revoked == false && control?.isCurrent == true && !Task.isCancelled
            })
        delivery = prepared
        let receipt = await prepared.commit()
        await prepared.close()
        delivery = nil
        return SessionCompletion(transcript: "", text: text, acceptance: .delivery(receipt), outputMutation: .preserve)
    }

    package func revoke() { revoked = true }
    package func close() async { revoke(); await delivery?.close(); delivery = nil }
}
