import Foundation
import XCTest
import UtterContracts
@testable import UtterSession

@MainActor
final class RestoreSelectionEditJobTests: XCTestCase {
    func testOriginalUnicodeSelectionUsesOneBoundTransactionAndCannotReplay() async throws {
        let original = "  原文 e\u{301} 👩🏽‍💻\n" + String(repeating: "第二行 🇸🇬 细节。", count: 100) + "\n  "
        let fixture = RestoreFixture(original: original)
        let sessionID = UUID()
        let job = try fixture.job(sessionID: sessionID)
        let completion = try await job.run(control: fixture.control)
        XCTAssertEqual(completion.text, original)
        XCTAssertNil(completion.record)
        XCTAssertNil(completion.historyReplacement)
        XCTAssertNil(completion.followup)
        XCTAssertEqual(completion.acceptance.deliveryStatus, .inserted)
        XCTAssertEqual(fixture.output.requests.count, 1)
        let request = try XCTUnwrap(fixture.output.requests.first)
        XCTAssertEqual(request.id, sessionID)
        XCTAssertFalse(request.allowsClipboardPaste)
        guard case .replaceAnchor(let text, let anchor) = request.command else { return XCTFail("Restore deleted the insertion") }
        XCTAssertEqual(text, original)
        XCTAssertTrue(anchor === fixture.anchor)
        XCTAssertEqual(anchor.range, NSRange(location: 9, length: "改写 🇸🇬".utf16.count))
        XCTAssertNil(fixture.outputs.snapshot.selectionEditRestoration)
        XCTAssertNil(fixture.outputs.recent)
        XCTAssertEqual(fixture.outputs.snapshot.recentText, "")
        XCTAssertThrowsError(try fixture.job())
        do { _ = try await job.run(control: fixture.control); XCTFail("Consumed restoration replayed") }
        catch { XCTAssertEqual(error as? DeliveryError, .invalidTarget) }
        XCTAssertEqual(fixture.output.requests.count, 1)
        await job.close()
    }

    func testUncertainRestoreRetiresTheReceiptWithoutClaimingInsertion() async throws {
        let fixture = RestoreFixture()
        fixture.output.disposition = .uncertain
        let job = try fixture.job()
        let completion = try await job.run(control: fixture.control)
        XCTAssertEqual(completion.acceptance.deliveryStatus, .uncertain)
        XCTAssertFalse(completion.accepted)
        XCTAssertThrowsError(try fixture.job())
        XCTAssertNil(fixture.outputs.snapshot.selectionEditRestoration)
        XCTAssertEqual(fixture.output.requests.count, 1)
    }

    func testLaterInputFocusAndNewerReceiptBlockReservedRestoreWithoutEffects() async throws {
        for invalidation in 0..<3 {
            let fixture = RestoreFixture()
            let job = try fixture.job()
            if invalidation == 0 { fixture.anchor.current = false }
            else if invalidation == 1 { fixture.target.isCurrent = false }
            else { fixture.remember(operationID: UUID()) }
            do { _ = try await job.run(control: fixture.control); XCTFail("Stale restoration committed") }
            catch { XCTAssertEqual(error as? DeliveryError, .invalidTarget) }
            XCTAssertTrue(fixture.output.requests.isEmpty)
        }
    }

    func testWrongReceiptAndRevokedJobCannotPrepareAnOutput() async throws {
        let fixture = RestoreFixture()
        XCTAssertThrowsError(try RestoreSelectionEditJob(operationID: UUID(), sessionID: UUID(),
            outputs: fixture.outputs, output: fixture.output, authorize: {}))
        let job = try fixture.job()
        job.revoke()
        do { _ = try await job.run(control: fixture.control); XCTFail("Cancelled restore committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertEqual(fixture.outputs.snapshot.selectionEditRestoration?.operationID, fixture.operationID)
    }
}

@MainActor
private final class RestoreFixture {
    let operationID = UUID()
    let recordID = UUID()
    let target = RestoreTarget()
    let output = RestoreOutput()
    let outputs = SessionOutputState(notifications: StateNotifications())
    let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
    let anchor: RestoreAnchor
    let original: String
    init(original: String = "原文 e\u{301} 👩🏽‍💻\n第二行") {
        self.original = original; anchor = RestoreAnchor(target: target); remember(operationID: operationID)
    }
    func remember(operationID: UUID) {
        let edit = SelectionEditReceipt(operationID: operationID, originalSelection: original,
            replacement: anchor.text, anchor: anchor)
        let receipt = DeliveryReceipt(operationID: operationID, disposition: .accepted, effect: .accessibility,
            anchor: anchor, confirmation: .targetValue, selectionEdit: edit)
        outputs.remember(SessionCompletion(transcript: "改写", text: anchor.text, acceptance: .delivery(receipt)), recordID: recordID)
    }
    func job(sessionID: UUID = UUID()) throws -> RestoreSelectionEditJob {
        try RestoreSelectionEditJob(operationID: operationID, sessionID: sessionID,
            outputs: outputs, output: output, authorize: {})
    }
}

@MainActor
private final class RestoreTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 3
    let context = InputContext(outputMode: .processed, inputLanguage: .chinese, source: .menuBar)
    let isValid = true
    var isCurrent = true
}

@MainActor
private final class RestoreAnchor: OutputAnchor {
    let target: any OutputTargetLease
    let text = "改写 🇸🇬"
    var range: NSRange { NSRange(location: 9, length: text.utf16.count) }
    let expiresAt = Date().addingTimeInterval(15)
    var current = true
    var isCurrent: Bool { current && Date() < expiresAt }
    init(target: any OutputTargetLease) { self.target = target }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? { nil }
}

@MainActor
private final class RestoreOutput: OutputService, PreparedDelivery {
    var disposition = DeliveryDisposition.accepted
    var requests: [DeliveryRequest] = []
    var receipt: DeliveryReceipt?
    func prepare(_ request: DeliveryRequest, isSessionCurrent: @escaping () -> Bool) throws -> any PreparedDelivery {
        guard isSessionCurrent() else { throw CancellationError() }
        requests.append(request)
        return self
    }
    func commit() async -> DeliveryReceipt {
        let receipt = DeliveryReceipt(operationID: requests.last!.id, disposition: disposition,
            effect: .accessibility, confirmation: .targetValue)
        self.receipt = receipt
        return receipt
    }
    func close() async {}
}
