import XCTest
@testable import UtterKeyboardBridge

final class VoiceKeyGestureTests: XCTestCase {
    private var gesture = VoiceKeyGesture()

    override func setUp() { gesture = VoiceKeyGesture() }

    func testPressFromIdleStartsImmediately() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
    }

    func testShortPressKeepsRecordingAndNextTapStops() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 0.12, voice: .starting), .none)
        XCTAssertEqual(gesture.press(at: 5, voice: .recording), .none)
        XCTAssertEqual(gesture.release(at: 5.1, voice: .recording), .stop)
    }

    func testShortPressReleasedAfterRecordingBeganStillKeepsRecording() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 0.39, voice: .recording), .none)
    }

    func testHoldReleaseStopsOnceRecordingBegan() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 2.5, voice: .recording), .stop)
    }

    func testHoldAtThresholdCountsAsHold() {
        XCTAssertEqual(gesture.press(at: 10, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 10 + VoiceKeyGesture.holdThreshold, voice: .recording), .stop)
    }

    func testHoldReleasedBeforeStartIsConfirmedCancelsSoItCannotStartLate() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 0.5, voice: .starting), .cancel)
    }

    func testHoldWhoseStartFailedHasNothingToEnd() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 3, voice: .idle), .none)
        XCTAssertEqual(gesture.release(at: 3, voice: .finishing), .none)
    }

    func testHoldEndsEvenWhenTheTouchIsCancelledOrLeavesTheKey() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 1, voice: .recording, inside: false, cancelled: true), .stop)
        XCTAssertEqual(gesture.press(at: 9, voice: .idle), .start)
        XCTAssertEqual(gesture.release(at: 10, voice: .recording, inside: false), .stop)
    }

    func testStopTapDoesNotStopWhenReleasedOutsideOrCancelled() {
        XCTAssertEqual(gesture.press(at: 0, voice: .recording), .none)
        XCTAssertEqual(gesture.release(at: 0.1, voice: .recording, inside: false), .none)
        XCTAssertEqual(gesture.press(at: 1, voice: .recording), .none)
        XCTAssertEqual(gesture.release(at: 1.1, voice: .recording, cancelled: true), .none)
    }

    func testStopTapStopsEvenAfterALongPress() {
        XCTAssertEqual(gesture.press(at: 0, voice: .recording), .none)
        XCTAssertEqual(gesture.release(at: 3, voice: .recording), .stop)
    }

    func testStopTapDoesNothingIfRecordingAlreadyEnded() {
        XCTAssertEqual(gesture.press(at: 0, voice: .recording), .none)
        XCTAssertEqual(gesture.release(at: 0.1, voice: .finishing), .none)
    }

    func testPressesWhileStartingOrFinishingAreIgnored() {
        for voice in [VoiceKeyGesture.Voice.starting, .finishing] {
            XCTAssertEqual(gesture.press(at: 0, voice: voice), .none)
            XCTAssertEqual(gesture.release(at: 2, voice: .recording), .none)
        }
    }

    func testSecondPressWhileOneIsActiveIsIgnored() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        XCTAssertEqual(gesture.press(at: 0.1, voice: .idle), .none)
        XCTAssertEqual(gesture.release(at: 0.2, voice: .starting), .none)
        XCTAssertEqual(gesture.press(at: 1, voice: .idle), .start)
    }

    func testReleaseWithoutPressDoesNothing() {
        XCTAssertEqual(gesture.release(at: 1, voice: .recording), .none)
    }

    func testResetForgetsTheActivePress() {
        XCTAssertEqual(gesture.press(at: 0, voice: .idle), .start)
        gesture.reset()
        XCTAssertEqual(gesture.release(at: 3, voice: .recording), .none)
    }

    func testAccessibilityActivationHasTapSemantics() {
        XCTAssertEqual(gesture.activate(voice: .idle), .start)
        XCTAssertEqual(gesture.activate(voice: .recording), .stop)
        XCTAssertEqual(gesture.activate(voice: .starting), .none)
        XCTAssertEqual(gesture.activate(voice: .finishing), .none)
    }
}
