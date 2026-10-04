import Foundation
import XCTest
import UtterContracts
import UtterSession

@MainActor
final class SessionOutputStateTests: XCTestCase {
    func testAStaleFormatterCannotChangeANewerPendingReplacement() async {
        let state = SessionOutputState(notifications: StateNotifications())
        let firstID = UUID()
        let firstAnchor = OutputStateAnchor(text: "first")
        state.remember(completion("first", anchor: firstAnchor), recordID: firstID)
        let first = pending(recordID: firstID, text: "first")
        XCTAssertTrue(state.installPending(first, anchor: firstAnchor))
        let secondID = UUID()
        let secondAnchor = OutputStateAnchor(text: "second")
        state.remember(completion("second", anchor: secondAnchor), recordID: secondID)
        let second = pending(recordID: secondID, text: "second")
        XCTAssertTrue(state.installPending(second, anchor: secondAnchor))
        XCTAssertFalse(state.updatePending(first.id) { $0.formattedText = "late"; $0.state = .ready })
        state.clearPending(first.id)
        XCTAssertEqual(state.snapshot.pending?.id, second.id)
        XCTAssertEqual(state.snapshot.pending?.historyRecordID, secondID)
        XCTAssertTrue(state.updatePending(second.id) { $0.formattedText = "Second."; $0.state = .ready })
        XCTAssertEqual(state.snapshot.pending?.formattedText, "Second.")
    }

    func testUncertainDeliveryAndAnUnrelatedAnchorCannotReplaceTheAcceptedState() async {
        let state = SessionOutputState(notifications: StateNotifications())
        let recordID = UUID()
        let anchor = OutputStateAnchor(text: "accepted")
        state.remember(completion("accepted", anchor: anchor), recordID: recordID)
        state.remember(completion("uncertain", disposition: .uncertain), recordID: UUID())
        XCTAssertEqual(state.recent?.recordID, recordID)
        XCTAssertEqual(state.snapshot.recentText, "accepted")
        let replacement = pending(recordID: recordID, text: "accepted")
        XCTAssertFalse(state.installPending(replacement, anchor: OutputStateAnchor(text: "accepted")))
        XCTAssertTrue(state.installPending(replacement, anchor: anchor))
        let resultOnly = SessionCompletion(transcript: "API", text: "API", acceptance: .returnedText)
        state.remember(resultOnly, recordID: UUID())
        XCTAssertEqual(state.snapshot.pending?.id, replacement.id)
        state.remember(completion(""), recordID: UUID())
        XCTAssertNil(state.recent)
        XCTAssertNil(state.snapshot.pending)
    }

    func testRetiredStateRejectsQueuedNotificationsAndLateFormatterCallbacks() async {
        let notifications = StateNotifications()
        let state = SessionOutputState(notifications: notifications)
        var callbacks = 0
        _ = state.observe { _ in callbacks += 1 }
        let recordID = UUID()
        let anchor = OutputStateAnchor(text: "accepted")
        let replacement = pending(recordID: recordID, text: "accepted")
        notifications.settle {
            state.remember(completion("accepted", anchor: anchor), recordID: recordID)
            XCTAssertTrue(state.installPending(replacement, anchor: anchor))
            state.close()
        }
        XCTAssertEqual(callbacks, 0)
        XCTAssertFalse(state.updatePending(replacement.id) { $0.formattedText = "late" })
        state.remember(completion("late"), recordID: UUID())
        XCTAssertEqual(state.snapshot, SessionOutputSnapshot())
    }

    private func pending(recordID: UUID, text: String) -> DeferredReplacement {
        DeferredReplacement(historyRecordID: recordID, rawText: text, insertedText: text,
            targetPID: 1, targetBundleIdentifier: "fixture.editor", message: "Formatting")
    }
    private func completion(_ text: String, anchor: (any OutputAnchor)? = nil,
                            disposition: DeliveryDisposition = .accepted) -> SessionCompletion {
        SessionCompletion(transcript: text, text: text, acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: disposition, effect: .paste, anchor: anchor)))
    }
}

@MainActor
private final class OutputStateAnchor: OutputAnchor {
    let target: any OutputTargetLease = OutputStateTarget()
    let text: String
    let range: NSRange
    let expiresAt = Date().addingTimeInterval(15)
    let isCurrent = true
    init(text: String) { self.text = text; range = NSRange(location: 0, length: (text as NSString).length) }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? { nil }
}
@MainActor
private final class OutputStateTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 1
    let context = InputContext(outputMode: .processed, inputLanguage: .english, source: .menuBar)
    let isValid = true
    let isCurrent = true
}
