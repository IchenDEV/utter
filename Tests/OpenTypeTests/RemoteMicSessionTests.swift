import Foundation
import XCTest
@testable import OpenType

/// Counterexamples for the remote voice-key session lifecycle.
final class RemoteMicSessionTests: XCTestCase {
    // MARK: - The "release before start commits" case

    func testReleaseBeforeStartCommitsCancelsThePendingStart() {
        var session = RemoteMicSession()
        let token = session.press()
        XCTAssertTrue(session.isStarting)

        XCTAssertTrue(session.release(), "a release before the start commits must cancel it")
        XCTAssertFalse(session.isLive)

        XCTAssertFalse(
            session.commitStart(token: token),
            "the cancelled start must not begin recording"
        )
        XCTAssertFalse(session.isRecording)
    }

    func testLateStartCompletionAfterReleaseIsRejected() {
        var session = RemoteMicSession()
        let first = session.press()
        _ = session.release()

        // A second, independent press starts before the stale completion lands.
        let second = session.press()
        XCTAssertFalse(
            session.commitStart(token: first),
            "a stale token cannot commit the new generation"
        )
        XCTAssertTrue(session.commitStart(token: second))
        XCTAssertTrue(session.isRecording)
    }

    func testDisconnectBeforeStartCompletesCancelsIt() {
        var session = RemoteMicSession()
        let token = session.press()
        XCTAssertTrue(session.invalidate(), "disconnect must invalidate a pending start")
        XCTAssertFalse(session.commitStart(token: token))
        XCTAssertFalse(session.isLive)
    }

    // MARK: - The normal path

    func testNormalPressStartReleaseStop() {
        var session = RemoteMicSession()
        let token = session.press()
        XCTAssertTrue(session.commitStart(token: token))
        XCTAssertTrue(session.isRecording)
        XCTAssertTrue(session.release())
        XCTAssertFalse(session.isLive)
    }

    func testStartMayOnlyCommitOnce() {
        var session = RemoteMicSession()
        let token = session.press()
        XCTAssertTrue(session.commitStart(token: token))
        XCTAssertFalse(session.commitStart(token: token), "a second commit must be rejected")
        XCTAssertTrue(session.isRecording)
    }

    func testReleaseWithoutPressDoesNothing() {
        var session = RemoteMicSession()
        XCTAssertFalse(session.release(), "no session to stop")
        XCTAssertFalse(session.invalidate())
    }

    func testDoubleReleaseStopsOnlyOnce() {
        var session = RemoteMicSession()
        let token = session.press()
        _ = session.commitStart(token: token)
        XCTAssertTrue(session.release())
        XCTAssertFalse(session.release(), "the second release must not report again")
    }

    func testRapidPressesKeepOnlyTheLatestGeneration() {
        var session = RemoteMicSession()
        let first = session.press()
        let second = session.press()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(session.commitStart(token: first))
        XCTAssertTrue(session.commitStart(token: second))
    }

    func testInvalidateWhileRecordingReportsLive() {
        var session = RemoteMicSession()
        let token = session.press()
        _ = session.commitStart(token: token)
        XCTAssertTrue(session.invalidate(), "closing the feature while recording must stop it")
        XCTAssertFalse(session.isLive)
    }
}

/// The pre-roll must retain the opening audio without growing without bound.
final class RemoteMicPreRollTests: XCTestCase {
    func testDrainReturnsChunksInOrder() {
        var preRoll = RemoteMicPreRoll(capacity: 4)
        preRoll.append([1, 2])
        preRoll.append([3, 4])

        XCTAssertEqual(preRoll.retainedChunks, 2)
        XCTAssertEqual(preRoll.retainedFrames, 4)
        XCTAssertEqual(preRoll.drain(), [[1, 2], [3, 4]])
        XCTAssertTrue(preRoll.isEmpty, "drain empties the buffer")
    }

    func testBoundedBufferDropsOldestChunks() {
        var preRoll = RemoteMicPreRoll(capacity: 2)
        preRoll.append([1])
        preRoll.append([2])
        preRoll.append([3])

        XCTAssertEqual(preRoll.retainedChunks, 2, "must not grow past capacity")
        XCTAssertEqual(preRoll.drain(), [[2], [3]], "oldest chunk dropped")
    }

    func testEmptySamplesAreIgnored() {
        var preRoll = RemoteMicPreRoll()
        preRoll.append([])
        XCTAssertTrue(preRoll.isEmpty)
    }

    func testResetClearsEverything() {
        var preRoll = RemoteMicPreRoll()
        preRoll.append([1, 2, 3])
        preRoll.reset()
        XCTAssertTrue(preRoll.isEmpty)
        XCTAssertEqual(preRoll.retainedFrames, 0)
    }
}

/// The bridge's event ordering: the session must latch on the start event, and a
/// stop that arrives before the pipeline commits must cancel it.
final class RemoteMicSessionOrderingTests: XCTestCase {
    /// `START_SEARCH → AUDIO_START → AUDIO → AUDIO_STOP`.
    func testStartSearchThenAudioStartThenStop() {
        var session = RemoteMicSession()
        // AUDIO_START latches the session.
        let token = session.press()
        XCTAssertTrue(session.isStarting)

        // AUDIO frames arrive while starting; they are pre-rolled, not dropped.
        var preRoll = RemoteMicPreRoll(capacity: 4)
        preRoll.append([1, 2])
        preRoll.append([3, 4])
        XCTAssertFalse(preRoll.isEmpty)

        // The pipeline commits.
        XCTAssertTrue(session.commitStart(token: token))
        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(preRoll.drain().flatMap { $0 }, [1, 2, 3, 4])

        // AUDIO_STOP.
        XCTAssertTrue(session.release())
        XCTAssertFalse(session.isLive)
    }

    /// Direct `AUDIO_START → AUDIO → AUDIO_STOP` (no `START_SEARCH`).
    func testDirectAudioStartThenStop() {
        var session = RemoteMicSession()
        let token = session.press()
        XCTAssertTrue(session.commitStart(token: token))
        XCTAssertTrue(session.release())
    }

    /// A short press: AUDIO_START then AUDIO_STOP before the pipeline commits.
    func testShortPressDoesNotStartArecording() {
        var session = RemoteMicSession()
        let token = session.press()
        // Stop lands first.
        XCTAssertTrue(session.release())
        // The late commit must be rejected.
        XCTAssertFalse(session.commitStart(token: token))
        XCTAssertFalse(session.isRecording)
    }

    /// Closing the feature mid-start must end the session.
    func testDeactivateMidStartEndsSession() {
        var session = RemoteMicSession()
        let token = session.press()
        XCTAssertTrue(session.invalidate())
        XCTAssertFalse(session.commitStart(token: token))
        XCTAssertFalse(session.isLive)
    }
}
