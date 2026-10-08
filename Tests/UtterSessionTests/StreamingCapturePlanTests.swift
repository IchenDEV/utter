import XCTest
@testable import UtterSession

final class StreamingCapturePlanTests: XCTestCase {
    func testEarlyBuffersRequireFullFileRecognition() {
        let plan = StreamingCapturePlan()
        XCTAssertFalse(plan.receiveBuffer())
        XCTAssertFalse(plan.beginStreaming())
        XCTAssertFalse(plan.finish())
    }

    func testWarmStreamingStartsOnlyBeforeTheFirstBufferAndStopsAtTheTail() {
        let plan = StreamingCapturePlan()
        XCTAssertTrue(plan.beginStreaming())
        XCTAssertTrue(plan.receiveBuffer())
        XCTAssertTrue(plan.finish())
        XCTAssertFalse(plan.receiveBuffer())
        XCTAssertFalse(plan.beginStreaming())
    }

    func testEndingCaptureDuringModelWaitCannotStartAStreamLater() {
        let plan = StreamingCapturePlan()
        XCTAssertFalse(plan.finish())
        XCTAssertFalse(plan.beginStreaming())
    }
}
