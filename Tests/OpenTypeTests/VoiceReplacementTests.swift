import UtterMediaContracts
import UtterPresentationContracts
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterSession

@MainActor
final class VoiceReplacementTests: XCTestCase {
    func testAcceptedReplacementAfterCancellationUpdatesOnlyOriginalHistoryRecord() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let (pending, original) = try installPending(fixture)
        let history = try fixture.runtime.service(DataServices.history)
        let unrelated = InputRecord(rawText: "Other", processedText: "Other", wasProcessed: false)
        history.addRecord(unrelated)
        fixture.output.delivery.heldCommit = true
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local, operation: .applyReplacement(pending.id))
        try driver.start(intent)
        while !fixture.output.delivery.committing { await Task.yield() }
        driver.cancel()
        fixture.output.delivery.releaseCommit()
        let result = try await driver.waitForCompletion(intent.id)
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(history.records.map(\.id), [unrelated.id, original.id])
        XCTAssertEqual(history.records.first?.processedText, "Other")
        XCTAssertEqual(history.records.last?.processedText, "Formatted text")
        XCTAssertEqual(fixture.output.requests.first?.id, intent.id)
        guard case .replaceAnchor = fixture.output.requests.first?.command else { return XCTFail("Missing anchored replacement") }
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        try await fixture.runtime.stop()
    }

    func testExpiredReplacementCopiesWithoutUpdatingHistoryOrRecentInsertion() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let (pending, original) = try installPending(fixture, createdAt: Date().addingTimeInterval(-20))
        let outputs = try fixture.runtime.service(SessionServices.outputs)
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local, operation: .applyReplacement(pending.id))
        try driver.start(intent)
        _ = try await driver.waitForCompletion(intent.id)
        guard case .clipboard(let text) = fixture.output.requests.first?.command else { return XCTFail("Expired replacement did not use explicit copy recovery") }
        XCTAssertEqual(text, "Formatted text")
        XCTAssertEqual(try fixture.runtime.service(DataServices.history).records.first?.processedText, original.processedText)
        XCTAssertEqual(outputs.snapshot.recentText, "Quick text")
        XCTAssertEqual(outputs.snapshot.pending?.state, .copied)
        try await fixture.runtime.stop()
    }

    private func installPending(_ fixture: VoiceWorkflowFixture, createdAt: Date = Date()) throws -> (DeferredReplacement, InputRecord) {
        let record = InputRecord(rawText: "Raw", processedText: "Quick text", wasProcessed: false)
        try fixture.runtime.service(DataServices.history).addRecord(record)
        let outputs = try fixture.runtime.service(SessionServices.outputs)
        let anchor = EditingAnchor(target: fixture.target, text: "Quick text")
        outputs.remember(SessionCompletion(transcript: "Raw", text: anchor.text, acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, anchor: anchor, confirmation: .targetValue))), recordID: record.id)
        var pending = DeferredReplacement(historyRecordID: record.id, rawText: "Raw", insertedText: anchor.text,
            targetPID: fixture.target.processIdentifier, targetBundleIdentifier: fixture.target.context.bundleIdentifier,
            message: "Ready", createdAt: createdAt)
        pending.formattedText = "Formatted text"
        pending.state = .ready
        XCTAssertTrue(outputs.installPending(pending, anchor: anchor))
        return (pending, record)
    }
}
