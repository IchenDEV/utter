import Foundation
import XCTest
import UtterContracts
@testable import UtterSession

@MainActor
final class SelectionReceiptRetentionTests: XCTestCase {
    func testConsumeClearsOriginalCandidateAnchorAndProjectionOnce() {
        let state = SessionOutputState(notifications: StateNotifications())
        let operationID = UUID()
        var anchor: ExpiringSelectionAnchor? = ExpiringSelectionAnchor(expiresAt: Date().addingTimeInterval(15))
        weak var retained = anchor
        remember(state, operationID: operationID, anchor: anchor!)
        anchor = nil
        XCTAssertEqual(state.snapshot.selectionEditRestoration?.originalSelection, "  原文 👩🏽‍💻\n  ")
        XCTAssertNotNil(retained)
        XCTAssertTrue(state.consumeSelectionEdit(operationID))
        XCTAssertFalse(state.consumeSelectionEdit(operationID))
        XCTAssertNil(state.recent)
        XCTAssertEqual(state.snapshot, SessionOutputSnapshot())
        XCTAssertNil(retained)
        state.close()
    }

    func testAutomaticExpiryClearsTextAndNotifiesWithoutAnotherUserAction() async throws {
        let state = SessionOutputState(notifications: StateNotifications())
        var observations: [SessionOutputSnapshot] = []
        _ = state.observe { observations.append($0) }
        var anchor: ExpiringSelectionAnchor? = ExpiringSelectionAnchor(expiresAt: Date().addingTimeInterval(0.05))
        weak var retained = anchor
        let id = UUID()
        remember(state, operationID: id, anchor: anchor!)
        anchor = nil
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while state.recent != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(state.recent)
        XCTAssertEqual(state.snapshot, SessionOutputSnapshot())
        XCTAssertEqual(observations.last, SessionOutputSnapshot())
        XCTAssertNil(retained)
        XCTAssertFalse(state.consumeSelectionEdit(id))
        state.close()
    }

    func testStaleExpiryCannotClearOrdinaryOrNewerSelectedOutput() {
        let state = SessionOutputState(notifications: StateNotifications())
        let oldID = UUID()
        remember(state, operationID: oldID, anchor: ExpiringSelectionAnchor(expiresAt: Date().addingTimeInterval(15)))
        state.remember(SessionCompletion(transcript: "normal", text: "normal", acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, confirmation: .targetValue))), recordID: UUID())
        state.expireSelectionEdit(oldID)
        XCTAssertEqual(state.snapshot.recentText, "normal")
        let newID = UUID()
        remember(state, operationID: newID, anchor: ExpiringSelectionAnchor(expiresAt: Date().addingTimeInterval(15)))
        state.expireSelectionEdit(oldID)
        XCTAssertEqual(state.snapshot.selectionEditRestoration?.operationID, newID)
        state.expireSelectionEdit(newID)
        XCTAssertEqual(state.snapshot, SessionOutputSnapshot())
        state.close()
    }

    func testCloseCancelsExpiryAndReleasesReceiptWithoutLateObservers() async throws {
        let state = SessionOutputState(notifications: StateNotifications())
        var calls = 0
        _ = state.observe { _ in calls += 1 }
        var anchor: ExpiringSelectionAnchor? = ExpiringSelectionAnchor(expiresAt: Date().addingTimeInterval(0.05))
        weak var retained = anchor
        remember(state, operationID: UUID(), anchor: anchor!)
        anchor = nil
        state.close()
        let before = calls
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(calls, before)
        XCTAssertNil(retained)
        XCTAssertEqual(state.snapshot, SessionOutputSnapshot())
    }

    private func remember(_ state: SessionOutputState, operationID: UUID, anchor: ExpiringSelectionAnchor) {
        let edit = SelectionEditReceipt(operationID: operationID, originalSelection: "  原文 👩🏽‍💻\n  ",
            replacement: anchor.text, anchor: anchor)
        let receipt = DeliveryReceipt(operationID: operationID, disposition: .accepted, effect: .accessibility,
            anchor: anchor, confirmation: .targetValue, selectionEdit: edit)
        state.remember(SessionCompletion(transcript: "rewrite", text: anchor.text, acceptance: .delivery(receipt)), recordID: UUID())
    }
}

@MainActor
private final class ExpiringSelectionAnchor: OutputAnchor {
    let target: any OutputTargetLease = ExpiringSelectionTarget()
    let text = "候选 🇸🇬"
    var range: NSRange { NSRange(location: 0, length: text.utf16.count) }
    let expiresAt: Date
    var isCurrent: Bool { Date() < expiresAt }
    init(expiresAt: Date) { self.expiresAt = expiresAt }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? { nil }
}

@MainActor
private final class ExpiringSelectionTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 2
    let context = InputContext(outputMode: .processed, inputLanguage: .chinese, source: .menuBar)
    let isValid = true
    let isCurrent = true
}
