import XCTest
import UtterContracts
@testable import UtterRemoteMic

/// Default timing: double-click window 0.4 s (press to press), long press 0.5 s, hold ceiling 10 s.
final class ButtonGestureRecognizerTests: XCTestCase {
    private func recognizer(double: Bool = false, long: Bool = false) -> ButtonGestureRecognizer {
        ButtonGestureRecognizer(bindings: GestureBindings(hasDouble: double, hasLong: long))
    }

    private func fire(_ gesture: ButtonGesture, _ at: TimeInterval) -> GestureFiring { GestureFiring(gesture, at: at) }

    // MARK: neither double nor long bound

    func testSingleOnlyFiresAtPressAndNotAgainOnHoldOrRelease() {
        var r = recognizer()
        XCTAssertEqual(r.press(at: 0), [fire(.single, 0)])
        XCTAssertEqual(r.advance(to: 5), [])
        XCTAssertEqual(r.release(at: 5), [])
        XCTAssertNil(r.nextDeadline)
    }

    func testSingleOnlyRapidPressesFireOncePerPress() {
        var r = recognizer()
        var fired: [GestureFiring] = []
        for t in stride(from: 0.0, to: 1.0, by: 0.2) {
            fired += r.press(at: t)
            fired += r.release(at: t + 0.05)
        }
        XCTAssertEqual(fired.map(\.gesture), Array(repeating: .single, count: 5))
    }

    // MARK: long only

    func testLongOnlyShortPressFiresSingleAtRelease() {
        var r = recognizer(long: true)
        XCTAssertEqual(r.press(at: 0), [])
        XCTAssertEqual(r.release(at: 0.2), [fire(.single, 0.2)])
    }

    func testLongOnlyFiresLongOnceAtThresholdWhileHeldAndConsumesRelease() {
        var r = recognizer(long: true)
        XCTAssertEqual(r.press(at: 0), [])
        XCTAssertEqual(r.nextDeadline, 0.5)
        XCTAssertEqual(r.advance(to: 0.6), [fire(.long, 0.5)])
        XCTAssertEqual(r.advance(to: 3), [])
        XCTAssertEqual(r.release(at: 3), [])
    }

    func testLongOnlyReleaseExactlyAtThresholdIsLongNotSingle() {
        var r = recognizer(long: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.release(at: 0.5), [fire(.long, 0.5)])
    }

    func testLongOnlyReleaseJustBeforeThresholdIsSingle() {
        var r = recognizer(long: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.release(at: 0.499), [fire(.single, 0.499)])
    }

    // MARK: double only

    func testDoubleOnlyFiresSingleWhenWindowEndsWithoutSecondPress() {
        var r = recognizer(double: true)
        XCTAssertEqual(r.press(at: 0), [])
        XCTAssertEqual(r.release(at: 0.1), [])
        XCTAssertEqual(r.nextDeadline, 0.4)
        XCTAssertEqual(r.advance(to: 0.39), [])
        XCTAssertEqual(r.advance(to: 0.5), [fire(.single, 0.4)])
        XCTAssertNil(r.nextDeadline)
    }

    func testDoubleOnlySecondPressInsideWindowFiresDoubleAtOnceAndNoSingleFollows() {
        var r = recognizer(double: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.press(at: 0.3), [fire(.double, 0.3)])
        XCTAssertEqual(r.release(at: 0.35), [])
        XCTAssertEqual(r.advance(to: 5), [])
    }

    func testDoubleOnlySecondPressExactlyAtWindowEndIsTooLate() {
        var r = recognizer(double: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.press(at: 0.4), [fire(.single, 0.4)])
        XCTAssertEqual(r.release(at: 0.45), [])
        XCTAssertEqual(r.advance(to: 1), [fire(.single, 0.8)])
    }

    func testDoubleOnlySecondPressJustInsideWindowIsDouble() {
        var r = recognizer(double: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.press(at: 0.399), [fire(.double, 0.399)])
    }

    func testDoubleOnlyPressHeldPastWindowResolvesAtReleaseNotWhileDown() {
        var r = recognizer(double: true)
        XCTAssertEqual(r.press(at: 0), [])
        XCTAssertEqual(r.advance(to: 0.45), [])
        XCTAssertEqual(r.release(at: 0.45), [fire(.single, 0.45)])
    }

    func testDoubleOnlyReleaseExactlyAtWindowEndIsSingleAtReleaseNotWaiting() {
        var r = recognizer(double: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.release(at: 0.4), [fire(.single, 0.4)])
        XCTAssertNil(r.nextDeadline)
    }

    func testDoubleOnlyReleaseJustInsideWindowWaitsForASecondPress() {
        var r = recognizer(double: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.release(at: 0.399), [])
        XCTAssertEqual(r.nextDeadline, 0.4)
    }

    // MARK: double and long

    func testBothFirstPressHeldToThresholdIsLongOnly() {
        var r = recognizer(double: true, long: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.advance(to: 0.6), [fire(.long, 0.5)])
        XCTAssertEqual(r.release(at: 0.6), [])
        XCTAssertEqual(r.advance(to: 5), [])
    }

    func testBothQuickPairIsDouble() {
        var r = recognizer(double: true, long: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.press(at: 0.25), [fire(.double, 0.25)])
    }

    func testBothSecondPressHeldLongStaysDoubleAndNeverBecomesLong() {
        var r = recognizer(double: true, long: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.press(at: 0.25), [fire(.double, 0.25)])
        XCTAssertEqual(r.advance(to: 2), [])
        XCTAssertEqual(r.release(at: 2), [])
    }

    func testBothPressReleasedBetweenWindowAndThresholdIsSingleAtRelease() {
        var r = recognizer(double: true, long: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.release(at: 0.45), [fire(.single, 0.45)])
    }

    func testBothQuickPressWithNoSecondFiresSingleAtWindowEnd() {
        var r = recognizer(double: true, long: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.advance(to: 1), [fire(.single, 0.4)])
    }

    // MARK: sequences, repeats, bad edges

    func testBackToBackDoublesEachFireOnce() {
        var r = recognizer(double: true)
        var fired: [GestureFiring] = []
        for start in [0.0, 0.35] {
            fired += r.press(at: start)
            fired += r.release(at: start + 0.05)
            fired += r.press(at: start + 0.15)
            fired += r.release(at: start + 0.2)
        }
        XCTAssertEqual(fired.map(\.gesture), [.double, .double])
    }

    func testThirdPressAfterDoubleStartsNewSequence() {
        var r = recognizer(double: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.press(at: 0.2), [fire(.double, 0.2)])
        _ = r.release(at: 0.25)
        XCTAssertEqual(r.press(at: 0.3), [])
        _ = r.release(at: 0.35)
        XCTAssertEqual(r.advance(to: 2), [fire(.single, 0.7)])
    }

    func testReleaseWithoutPressIsIgnored() {
        var r = recognizer(double: true, long: true)
        XCTAssertEqual(r.release(at: 1), [])
        XCTAssertNil(r.nextDeadline)
    }

    func testDuplicatePressWhileDownIsIgnored() {
        var r = recognizer(long: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.press(at: 0.1), [])
        XCTAssertEqual(r.advance(to: 0.6), [fire(.long, 0.5)])
    }

    func testMissedReleaseIsClosedAtCeilingAndNextPressStartsFresh() {
        var r = recognizer(double: true)
        XCTAssertEqual(r.press(at: 0), [])
        XCTAssertEqual(r.nextDeadline, 10)
        XCTAssertEqual(r.advance(to: 10), [])
        XCTAssertNil(r.nextDeadline)
        XCTAssertEqual(r.press(at: 11), [])
        _ = r.release(at: 11.05)
        XCTAssertEqual(r.advance(to: 12), [fire(.single, 11.4)])
    }

    func testLongFiredThenMissedReleaseIsClosedAtCeiling() {
        var r = recognizer(long: true)
        _ = r.press(at: 0)
        XCTAssertEqual(r.advance(to: 20), [fire(.long, 0.5)])
        XCTAssertNil(r.nextDeadline)
        XCTAssertEqual(r.press(at: 21), [])
    }

    func testLongThresholdNeverExceedsCeiling() {
        let timing = GestureTiming(doubleWindow: 0.4, longThreshold: 30, holdCeiling: 10)
        XCTAssertEqual(timing.longThreshold, 10)
    }

    func testAdvanceReportsEachGestureOnceAcrossAGap() {
        var r = recognizer(double: true)
        _ = r.press(at: 0)
        _ = r.release(at: 0.1)
        XCTAssertEqual(r.advance(to: 100), [fire(.single, 0.4)])
        XCTAssertEqual(r.advance(to: 200), [])
    }
}
