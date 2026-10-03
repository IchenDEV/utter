import UtterRemoteMic
import XCTest
@testable import OpenType

/// Couples the guard to the real bridge latch, so the test exercises the same
/// predicate the pipeline uses rather than a stand-in.
final class RemoteMicBridgeLatchTests: XCTestCase {
    func testBridgeReportsNoCurrentSessionWhenIdle() {
        let bridge = XiaomiRemoteMicBridge()
        bridge.deactivate()
        XCTAssertNil(bridge.currentSessionToken)
        XCTAssertFalse(XiaomiRemoteMicBridge.isSessionCurrent(1))
    }
}
