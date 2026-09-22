import XCTest
@testable import OpenType

/// The release path must not discard the recording it is about to transcribe.
///
/// The old commit called `cancelSession()` before `stopRecording()` on every
/// release; `cancelSession` nils `lastRecordingURL`, so the pipeline read nil
/// and had nothing to transcribe.
@MainActor
final class RemoteMicReleasePathTests: XCTestCase {
    /// A committed recording must stop, not be cancelled: cancelling nils the
    /// WAV that the pipeline is about to transcribe. This drives the production
    /// `applyRelease` wiring, not just the decision value.
    func testCommittedRecordingIsStoppedAndNotCancelled() {
        let target = FakeCaptureTarget(hasActiveRecording: true, isRunning: true)
        var stopped = false
        let decision = RemoteMicReleaseDecision.applyRelease(
            to: target,
            stopPipeline: { stopped = true }
        )

        XCTAssertEqual(target.cancelCount, 0, "a committed recording must not be cancelled (the WAV is needed)")
        XCTAssertTrue(stopped, "the pipeline must be stopped so it can transcribe")
        XCTAssertTrue(decision.shouldStopPipeline)
    }

    /// A start that never committed is cancelled, so nothing is recorded.
    func testUncommittedStartIsCancelledAndPipelineNotStopped() {
        let target = FakeCaptureTarget(hasActiveRecording: false, isRunning: true)
        var stopped = false
        _ = RemoteMicReleaseDecision.applyRelease(
            to: target,
            stopPipeline: { stopped = true }
        )

        XCTAssertEqual(target.cancelCount, 1, "the pending start must be abandoned")
        XCTAssertFalse(stopped, "nothing committed, so nothing to stop")
    }

    /// With no session at all, a release does nothing.
    func testIdleReleaseDoesNothing() {
        let target = FakeCaptureTarget(hasActiveRecording: false, isRunning: false)
        var stopped = false
        _ = RemoteMicReleaseDecision.applyRelease(
            to: target,
            stopPipeline: { stopped = true }
        )

        XCTAssertEqual(target.cancelCount, 0)
        XCTAssertFalse(stopped)
    }

    /// Disabling the feature while recording must stop the pipeline, because the
    /// bridge's release callback is suppressed once the setting is off.
    func testDisablingWhileRecordingStillStopsThePipeline() {
        let decision = RemoteMicShutdownDecision.decide(hasActiveRecording: true)
        XCTAssertTrue(decision.shouldStopPipeline)
    }

    func testDisablingWhileIdleDoesNotStop() {
        let decision = RemoteMicShutdownDecision.decide(hasActiveRecording: false)
        XCTAssertFalse(decision.shouldStopPipeline)
    }
}

/// A fake capture target for the release decision.
@MainActor
private final class FakeCaptureTarget: RemoteMicReleaseTarget {
    let hasActiveRecording: Bool
    let isRunning: Bool
    private(set) var cancelCount = 0

    init(hasActiveRecording: Bool, isRunning: Bool) {
        self.hasActiveRecording = hasActiveRecording
        self.isRunning = isRunning
    }

    func cancelSession() { cancelCount += 1 }
}

/// Idle or late audio must not enter the next session's pre-roll. This exercises
/// the production routing rule the bridge uses, not a copy of it.
final class RemoteMicAudioRoutingTests: XCTestCase {
    func testIdleAudioIsDropped() {
        XCTAssertEqual(RemoteMicAudioRouting.destination(for: .idle), .drop)
    }

    func testStartingAudioIsPreRolled() {
        XCTAssertEqual(RemoteMicAudioRouting.destination(for: .starting), .preRoll)
    }

    func testRecordingAudioIsForwarded() {
        XCTAssertEqual(RemoteMicAudioRouting.destination(for: .recording), .forward)
    }

    func testIdleToPressToReleaseKeepsOnlyTheStartingChunk() {
        var session = RemoteMicSession()
        var preRoll = RemoteMicPreRoll(capacity: 4)
        var forwarded = 0

        func deliver() {
            switch RemoteMicAudioRouting.destination(for: session.phase) {
            case .forward: forwarded += 1
            case .preRoll: preRoll.append([1])
            case .drop: break
            }
        }

        deliver() // idle: dropped
        XCTAssertTrue(preRoll.isEmpty)

        _ = session.press()
        deliver() // starting: buffered
        XCTAssertEqual(preRoll.retainedChunks, 1)

        _ = session.release()
        deliver() // late: dropped
        XCTAssertEqual(preRoll.retainedChunks, 1, "late audio must not pollute the next session")
        XCTAssertEqual(forwarded, 0)
    }
}
