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

    func testPreparationAndReturnedAPITextDoNotClaimInsertion() {
        let preparing = SessionPresentation(SessionExecutionSnapshot(phase: .preparing, isBusy: true))
        XCTAssertEqual(preparing.status, .preparing)
        XCTAssertFalse(preparing.canCopy)
        XCTAssertEqual(SessionPresentation(SessionExecutionSnapshot(phase: .completed, text: "API result")).status, .idle)
        XCTAssertEqual(SessionExecutionSnapshot(audioLevel: .nan).audioLevel, 0)
        XCTAssertEqual(SessionExecutionSnapshot(audioLevel: 2).audioLevel, 1)
    }
}
