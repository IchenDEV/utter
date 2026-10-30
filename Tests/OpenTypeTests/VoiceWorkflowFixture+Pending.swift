import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterSession

extension VoiceWorkflowFixture {
    @MainActor
    func installPending(createdAt: Date = Date()) throws -> (DeferredReplacement, InputRecord) {
        let record = InputRecord(rawText: "Raw", processedText: "Quick text", wasProcessed: false)
        try runtime.service(DataServices.history).addRecord(record)
        let outputs = try runtime.service(SessionServices.outputs)
        let anchor = EditingAnchor(target: target, text: "Quick text")
        outputs.remember(SessionCompletion(transcript: "Raw", text: anchor.text, acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, anchor: anchor, confirmation: .targetValue))), recordID: record.id)
        var pending = DeferredReplacement(historyRecordID: record.id, rawText: "Raw", insertedText: anchor.text,
            targetPID: target.processIdentifier, targetBundleIdentifier: target.context.bundleIdentifier,
            message: "Ready", createdAt: createdAt)
        pending.formattedText = "Formatted text"
        pending.state = .ready
        XCTAssertTrue(outputs.installPending(pending, anchor: anchor))
        return (pending, record)
    }
}
