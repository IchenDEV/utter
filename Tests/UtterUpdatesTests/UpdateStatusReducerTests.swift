import XCTest
import UtterContracts
@testable import UtterUpdates

final class UpdateStatusReducerTests: XCTestCase {
    private func run(_ start: UpdateStatus, _ events: [UpdateEvent]) -> UpdateStatus {
        events.reduce(start) { UpdateStatusReducer.reduce($0, $1) }
    }

    func testCheckWithNoUpdateEndsUpToDate() {
        XCTAssertEqual(run(.idle, [.checkStarted, .noUpdate, .cycleFinished]), .upToDate)
    }

    func testCheckThatFindsAnUpdateKeepsItVisibleAfterTheCycle() {
        XCTAssertEqual(run(.idle, [.checkStarted, .foundUpdate(version: "1.2.3"), .cycleFinished]), .available(version: "1.2.3"))
    }

    func testFailureIsReportedAndSurvivesTheCycleEnd() {
        XCTAssertEqual(run(.idle, [.checkStarted, .failed("offline"), .cycleFinished]), .failed("offline"))
    }

    func testCycleEndWithoutOutcomeReturnsToIdle() {
        XCTAssertEqual(run(.idle, [.checkStarted, .cycleFinished]), .idle)
    }

    func testRepeatedCheckDoesNotHideAKnownUpdate() {
        XCTAssertEqual(run(.available(version: "1.2.3"), [.checkStarted]), .available(version: "1.2.3"))
    }

    func testSkippingClearsTheAvailableUpdateOnly() {
        XCTAssertEqual(run(.available(version: "1.2.3"), [.skipped]), .idle)
        XCTAssertEqual(run(.upToDate, [.skipped]), .upToDate)
    }

    func testPendingRestartIsStickyUntilTheProcessExits() {
        let pending = UpdateStatus.pendingRestart(version: "1.2.3")
        XCTAssertEqual(run(.available(version: "1.2.3"), [.restartPending(version: "1.2.3")]), pending)
        XCTAssertEqual(run(pending, [.checkStarted, .noUpdate, .failed("x"), .cycleFinished, .skipped]), pending)
    }

    func testUnavailableNeverReportsActivity() {
        let inert = UpdateStatus.unavailable(.missingFeed)
        let events: [UpdateEvent] = [.checkStarted, .foundUpdate(version: "9"), .noUpdate, .failed("x"),
                                     .restartPending(version: "9"), .skipped, .cycleFinished]
        XCTAssertEqual(run(inert, events), inert)
        XCTAssertFalse(inert.isAvailable)
        XCTAssertTrue(UpdateStatus.idle.isAvailable)
    }
}
