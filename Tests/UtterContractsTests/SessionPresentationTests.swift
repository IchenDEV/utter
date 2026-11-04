import XCTest
import UtterContracts

final class SessionPresentationTests: XCTestCase {
    func testReceiptStatusDrivesDistinctTerminalPresentation() {
        let inserted = SessionPresentation(SessionExecutionSnapshot(phase: .completed, text: "text", deliveryStatus: .inserted))
        let copied = SessionPresentation(SessionExecutionSnapshot(phase: .completed, text: "text", deliveryStatus: .copied))
        let uncertain = SessionPresentation(SessionExecutionSnapshot(phase: .failed, text: "text", deliveryStatus: .uncertain))
        let failed = SessionPresentation(SessionExecutionSnapshot(phase: .failed, error: "Microphone unavailable"))
        XCTAssertEqual(inserted.status, .inserted)
        XCTAssertEqual(copied.status, .copied)
        XCTAssertEqual(uncertain.status, .uncertain)
        XCTAssertTrue(uncertain.keepsVisible)
        XCTAssertTrue(uncertain.canCopy)
        XCTAssertTrue(failed.keepsVisible)
        XCTAssertFalse(failed.canCopy)
        XCTAssertNotEqual(inserted.message, copied.message)
    }

    func testOnlyAnUnconfirmedInsertionMayLeaveTheScreenOnItsOwn() {
        func presentation(_ snapshot: SessionExecutionSnapshot) -> SessionPresentation { SessionPresentation(snapshot) }
        let uncertain = presentation(SessionExecutionSnapshot(phase: .failed, text: "text", deliveryStatus: .uncertain))
        XCTAssertTrue(uncertain.autoDismisses)
        XCTAssertTrue(uncertain.keepsVisible, "Interactive controls stay available while it is shown")
        XCTAssertFalse(presentation(SessionExecutionSnapshot(phase: .failed, error: "Model failed", recoveryAction: .models)).autoDismisses)
        XCTAssertFalse(presentation(SessionExecutionSnapshot(phase: .failed, text: "text", error: "Clipboard off", deliveryStatus: .notDelivered)).autoDismisses)
        XCTAssertFalse(presentation(SessionExecutionSnapshot(phase: .completed, text: "text", deliveryStatus: .inserted)).autoDismisses)
        XCTAssertFalse(presentation(SessionExecutionSnapshot(phase: .completed, text: "text", deliveryStatus: .copied)).autoDismisses)
        XCTAssertFalse(presentation(SessionExecutionSnapshot(phase: .recording, isBusy: true)).autoDismisses)
    }

    func testACompatibilityPasteIsQuietWhileAnUnconfirmedInsertionStaysANotice() {
        let compat = SessionPresentation(SessionExecutionSnapshot(phase: .completed, text: "text", deliveryStatus: .uncertain))
        XCTAssertEqual(compat.status, .inserted)
        XCTAssertFalse(compat.autoDismisses)
        XCTAssertEqual(compat.message, L("delivery.compat_pasted"))
        XCTAssertNotEqual(compat.message, L("status.done"))
        let unconfirmed = SessionPresentation(SessionExecutionSnapshot(phase: .failed, text: "text", deliveryStatus: .uncertain))
        XCTAssertEqual(unconfirmed.status, .uncertain)
    }

    func testPreparationAndReturnedAPITextDoNotClaimInsertion() {
        let preparing = SessionPresentation(SessionExecutionSnapshot(phase: .preparing, isBusy: true))
        XCTAssertEqual(preparing.status, .preparing)
        XCTAssertFalse(preparing.canCopy)
        XCTAssertEqual(SessionPresentation(SessionExecutionSnapshot(phase: .completed, text: "API result")).status, .idle)
        XCTAssertEqual(SessionExecutionSnapshot(audioLevel: .nan).audioLevel, 0)
        XCTAssertEqual(SessionExecutionSnapshot(audioLevel: 2).audioLevel, 1)
    }
}
