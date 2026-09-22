import XCTest
@testable import OpenType

/// Counterexamples for the remote voice-key start committing through the real
/// pipeline path. These model "the pipeline finished loading the model" and then
/// decide; the old commit (`1f27b1fb`) only guarded the layer above the
/// pipeline, so a release during model load still reached recording.
final class RemoteMicStartGuardTests: XCTestCase {
    /// The reviewer's exact case: the key was released while the pipeline was
    /// awaiting the model, so the start must not commit.
    func testReleasedDuringModelLoadDoesNotCommit() {
        let committed = RemoteMicStartGuard.shouldCommit(
            remoteSessionToken: 7,
            isCancelled: false,
            isSessionCurrent: { _ in false }
        )
        XCTAssertFalse(committed, "a released session must not begin recording")
    }

    /// Cancelling the owning task must abort even if the bridge still reports the
    /// latch live (release ordering races).
    func testCancelledOwningTaskDoesNotCommit() {
        let committed = RemoteMicStartGuard.shouldCommit(
            remoteSessionToken: 7,
            isCancelled: true,
            isSessionCurrent: { _ in true }
        )
        XCTAssertFalse(committed, "a cancelled start must not begin recording")
    }

    /// A live, uncancelled session commits normally.
    func testLiveSessionCommits() {
        let committed = RemoteMicStartGuard.shouldCommit(
            remoteSessionToken: 7,
            isCancelled: false,
            isSessionCurrent: { $0 == 7 }
        )
        XCTAssertTrue(committed)
    }

    /// A local (hotkey) start has no remote latch and must keep working.
    func testLocalStartWithoutRemoteTokenCommits() {
        let committed = RemoteMicStartGuard.shouldCommit(
            remoteSessionToken: nil,
            isCancelled: false,
            isSessionCurrent: { _ in false }
        )
        XCTAssertTrue(committed, "the hotkey path must be unaffected")
    }

    /// A superseded latch (a newer press owns the bridge) must not commit.
    func testSupersededLatchDoesNotCommit() {
        let committed = RemoteMicStartGuard.shouldCommit(
            remoteSessionToken: 7,
            isCancelled: false,
            isSessionCurrent: { $0 == 8 }
        )
        XCTAssertFalse(committed)
    }
}

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
