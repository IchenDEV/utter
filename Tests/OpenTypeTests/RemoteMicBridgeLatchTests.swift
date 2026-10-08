import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterRemoteMic
import XCTest
@testable import UtterPresentation

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
