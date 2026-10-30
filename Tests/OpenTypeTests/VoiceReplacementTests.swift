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
    func testRefusedLocalTargetCannotCopyPendingReplacement() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let (pending, original) = try fixture.installPending()
        fixture.targetAvailable = false
        let execution = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local, operation: .applyReplacement(pending.id))
        do {
            try execution.start(intent)
            _ = try await execution.waitForCompletion(intent.id)
            XCTFail("Refused capture became a pending replacement copy")
        } catch { XCTAssertEqual(error as? DeliveryError, .invalidTarget) }
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertEqual(try fixture.runtime.service(DataServices.history).records.first?.processedText, original.processedText)
        XCTAssertEqual(try fixture.runtime.service(SessionServices.outputs).snapshot.pending?.state, .ready)
        try await fixture.runtime.stop()
    }

    func testAcceptedReplacementAfterCancellationUpdatesOnlyOriginalHistoryRecord() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let (pending, original) = try fixture.installPending()
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
        let (pending, original) = try fixture.installPending(createdAt: Date().addingTimeInterval(-20))
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
}
