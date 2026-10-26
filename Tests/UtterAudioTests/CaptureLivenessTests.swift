import XCTest
@testable import UtterAudio

final class CaptureLivenessTests: XCTestCase {
    private let grace = CaptureLiveness.graceSeconds

    func testFramesMakeCaptureHealthyAtAnyTime() {
        for elapsed in [0, grace - 0.1, grace, grace * 10] {
            XCTAssertEqual(
                CaptureLiveness.decide(elapsed: elapsed, framesReceived: 1, retriesUsed: 0),
                .healthy
            )
            XCTAssertEqual(
                CaptureLiveness.decide(elapsed: elapsed, framesReceived: 4096, retriesUsed: 1),
                .healthy
            )
        }
    }

    func testZeroFramesWaitsWithinGracePeriod() {
        XCTAssertEqual(CaptureLiveness.decide(elapsed: 0, framesReceived: 0, retriesUsed: 0), .wait)
        XCTAssertEqual(
            CaptureLiveness.decide(elapsed: grace - 0.01, framesReceived: 0, retriesUsed: 0),
            .wait
        )
    }

    func testFirstExpiryRetriesOnce() {
        XCTAssertEqual(CaptureLiveness.decide(elapsed: grace, framesReceived: 0, retriesUsed: 0), .retry)
        XCTAssertEqual(
            CaptureLiveness.decide(elapsed: grace + 5, framesReceived: 0, retriesUsed: 0),
            .retry
        )
    }

    func testExpiryAfterRetryFails() {
        XCTAssertEqual(CaptureLiveness.decide(elapsed: grace, framesReceived: 0, retriesUsed: 1), .fail)
        XCTAssertEqual(CaptureLiveness.decide(elapsed: grace, framesReceived: 0, retriesUsed: 5), .fail)
    }

    func testRetryRestartsTheGracePeriod() {
        XCTAssertEqual(
            CaptureLiveness.decide(elapsed: 0.2, framesReceived: 0, retriesUsed: 1),
            .wait
        )
    }

    func testInvalidElapsedNeverTriggersRecovery() {
        XCTAssertEqual(CaptureLiveness.decide(elapsed: -1, framesReceived: 0, retriesUsed: 0), .wait)
        XCTAssertEqual(CaptureLiveness.decide(elapsed: .nan, framesReceived: 0, retriesUsed: 0), .wait)
        XCTAssertEqual(CaptureLiveness.decide(elapsed: .infinity, framesReceived: 0, retriesUsed: 0), .wait)
    }
}
