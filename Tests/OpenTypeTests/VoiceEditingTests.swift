import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterSession

@MainActor
final class VoiceEditingTests: XCTestCase {
    func testRewriteUsesFullFrozenSelectionAndReplacesItWithoutMicrophone() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.target.selectedText = String(repeating: "Entire selected sentence. ", count: 100)
        fixture.recipe.resolution = .command(.rewriteSelection(.formal))
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        try driver.start(SessionIntent(input: .text("Make the selection formal"), mode: .command))
        let result = try await driver.waitForCompletion(try XCTUnwrap(driver.snapshot.id))
        XCTAssertEqual(fixture.recipe.requests.first?.text, fixture.target.selectedText)
        XCTAssertEqual(fixture.recipe.requests.first?.mode, .selectionEdit(.formal, spokenCommand: "Make the selection formal"))
        XCTAssertLessThan(fixture.recipe.resolutionContexts.first?.selectedTextPreview?.count ?? 0, 330)
        guard case .replaceSelection(let text) = fixture.output.requests.first?.command else { return XCTFail("Selection was inserted instead of replaced") }
        XCTAssertEqual(text, result.text)
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertEqual(try fixture.runtime.service(DataServices.history).records.count, 1)
        try await fixture.runtime.stop()
    }

    func testUndoUsesAcceptedAnchorAndDoesNotAddHistory() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let outputs = try fixture.runtime.service(SessionServices.outputs)
        let history = try fixture.runtime.service(DataServices.history)
        let anchor = EditingAnchor(target: fixture.target, text: "Original text")
        outputs.remember(SessionCompletion(transcript: "original", text: anchor.text, acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, anchor: anchor, confirmation: .targetValue))), recordID: UUID())
        fixture.recipe.resolution = .command(.undoLastInsertion)
        let driver = try fixture.runtime.service(SessionServices.execution)
        try driver.start(SessionIntent(input: .text("Undo"), mode: .command))
        _ = try await driver.waitForCompletion(try XCTUnwrap(driver.snapshot.id))
        guard case .undoAnchor(let used) = fixture.output.requests.first?.command else { return XCTFail("Missing anchored undo") }
        XCTAssertTrue(used === anchor)
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertNil(outputs.recent)
        try await fixture.runtime.stop()
    }

    func testExpiredAnchorFailsWithoutReinterpretingCommandAsDictation() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let anchor = EditingAnchor(target: fixture.target, text: "Original text")
        try fixture.runtime.service(SessionServices.outputs).remember(SessionCompletion(transcript: "original", text: anchor.text, acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, anchor: anchor, confirmation: .targetValue))), recordID: UUID())
        fixture.recipe.resolution = .command(.replaceLast("Replacement"))
        anchor.isCurrent = false
        let driver = try fixture.runtime.service(SessionServices.execution)
        try driver.start(SessionIntent(input: .text("Replace that"), mode: .command))
        do { _ = try await driver.waitForCompletion(try XCTUnwrap(driver.snapshot.id)); XCTFail("Stale anchor committed") }
        catch { XCTAssertEqual(error as? DeliveryError, .invalidTarget) }
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertTrue(fixture.recipe.requests.isEmpty)
        XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
        try await fixture.runtime.stop()
    }
}

@MainActor
final class EditingAnchor: OutputAnchor {
    let target: any OutputTargetLease
    let range: NSRange
    let text: String
    let expiresAt = Date().addingTimeInterval(15)
    var isCurrent = true
    init(target: any OutputTargetLease, text: String) {
        self.target = target; self.text = text; range = NSRange(location: 0, length: text.utf16.count)
    }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? { nil }
}
