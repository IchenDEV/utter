import AVFoundation
import XCTest
@testable import OpenType

/// A minimal engine that reports ready without touching models, used to drive
/// the real `VoicePipeline.start` await in a test.
private final class PipelineTestEngine: SpeechEngine, @unchecked Sendable {
    var isReady: Bool { true }
    func transcribe(audioURL: URL?, language: String?) async throws -> String { "ok" }
}

/// Records whether capture was reached. `AudioCaptureManager` is final, so the
/// observation point is the injected remote source rather than a subclass.
@MainActor
final class CaptureSpySource: RemoteMicCaptureSpy {
    private(set) var startInvocations = 0
    private(set) var startTokens: [UInt64] = []
    var currentToken: UInt64?
    var startResult = true

    func start(token: UInt64) -> Bool {
        startInvocations += 1
        startTokens.append(token)
        return startResult
    }
}

/// Counterexamples that cross the real `VoicePipeline.start` await and the
/// AppDelegate release path, rather than only the pure helpers.
@MainActor
final class RemoteMicPipelineIntegrationTests: XCTestCase {
    private func makePipeline() -> (VoicePipeline, AppState, CaptureSpySource) {
        let state = AppState()
        let pipeline = VoicePipeline(appState: state)
        let spy = CaptureSpySource()
        pipeline.remoteCaptureSpy = spy
        pipeline.engineOverride = PipelineTestEngine()
        return (pipeline, state, spy)
    }

    /// The old commit only guarded the layer above the pipeline: a release
    /// during the model wait still reached recording.
    func testReleaseDuringModelLoadDoesNotReachRecordingOrCaptureStart() async {
        let (pipeline, state, spy) = makePipeline()
        let token = XiaomiRemoteMicBridge.shared.beginSimulatedSessionForTesting()

        // Hold the pipeline inside the model-load await.
        let gate = AsyncGate()
        pipeline.engineLoadBarrier = { await gate.wait() }

        let startTask = Task {
            await pipeline.start(mode: .dictation, remoteSessionToken: token)
        }
        await gate.waitUntilEntered()

        // The user lets go while the model is still loading.
        _ = XiaomiRemoteMicBridge.shared.endSimulatedSessionForTesting()
        await gate.open()
        await startTask.value

        XCTAssertFalse(state.isRecording, "a released start must not reach recording")
        XCTAssertEqual(spy.startInvocations, 0, "capture (and the system-mic fallback) must not start")
    }

    /// A live session commits normally through the same await.
    func testLiveSessionCommitsThroughTheRealAwait() async {
        let (pipeline, state, spy) = makePipeline()
        let token = XiaomiRemoteMicBridge.shared.beginSimulatedSessionForTesting()

        spy.currentToken = token
        let gate = AsyncGate()
        pipeline.engineLoadBarrier = { await gate.wait() }
        let startTask = Task {
            await pipeline.start(mode: .dictation, remoteSessionToken: token)
        }
        await gate.waitUntilEntered()
        await gate.open()
        await startTask.value

        XCTAssertTrue(state.isRecording, "a live session must proceed")
        XCTAssertEqual(spy.startInvocations, 1)
        _ = XiaomiRemoteMicBridge.shared.endSimulatedSessionForTesting()
    }

    /// A superseded latch must abort too.
    func testSupersededLatchDoesNotCommit() async {
        let (pipeline, state, spy) = makePipeline()
        let token = XiaomiRemoteMicBridge.shared.beginSimulatedSessionForTesting()

        let gate = AsyncGate()
        pipeline.engineLoadBarrier = { await gate.wait() }
        let startTask = Task {
            await pipeline.start(mode: .dictation, remoteSessionToken: token)
        }
        await gate.waitUntilEntered()
        // A newer press replaces the latch.
        _ = XiaomiRemoteMicBridge.shared.beginSimulatedSessionForTesting()
        await gate.open()
        await startTask.value

        XCTAssertFalse(state.isRecording)
        XCTAssertEqual(spy.startInvocations, 0)
    }

    /// A local hotkey start (no remote token) is unaffected.
    func testLocalStartWithoutTokenIsUnaffected() async {
        let (pipeline, state, _) = makePipeline()
        await pipeline.start(mode: .dictation)
        XCTAssertNotEqual(state.phase, .idle, "the hotkey path must still start")
    }
}

/// A two-ended gate with a deterministic "entered" signal, so the test never
/// depends on sleep ordering and cannot deadlock.
@MainActor
private final class AsyncGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var openWaiter: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        if isOpen { return }
        await withCheckedContinuation { openWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func open() {
        isOpen = true
        openWaiter?.resume()
        openWaiter = nil
    }
}

/// The attempt must be captured at callback *source*, not read as the live
/// generation when the callback is delivered. On a reused `CBPeripheral` the two
/// differ. The test retains the old production delegate proxy, starts a second
/// lifecycle on the same simulated peripheral, and sends the old event through
/// that proxy's real bridge route.
@MainActor
final class RemoteMicCallbackRoutingTests: XCTestCase {
    func testLateDisconnectFromOldSourceCannotInvalidateNewLifecycle() throws {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()

        // Attempt 1 installs a source-bound production delegate proxy.
        let firstAttempt = bridge.simulateConnectForTesting()
        XCTAssertEqual(bridge.attemptForCurrentPeripheralForTesting(), firstAttempt)
        let firstProxy = try XCTUnwrap(bridge.callbackProxyForTesting())

        // A new attempt begins on the same peripheral object and replaces only
        // the active lifecycle; the old proxy remains a valid queued-event
        // source carrying attempt 1.
        let secondAttempt = bridge.simulateReconnectSamePeripheralForTesting()
        XCTAssertGreaterThan(secondAttempt, firstAttempt)

        // This is the production proxy -> bridge route, not a direct helper
        // assertion. A live-generation lookup would tear down attempt 2 here.
        firstProxy.deliverForTesting(.disconnect)

        XCTAssertTrue(
            bridge.isAttemptActiveForTesting(secondAttempt),
            "a stale disconnect must not invalidate the replacement lifecycle"
        )
    }

    /// A stale control event must not release the live voice-key session after
    /// the replacement attempt has become the tracked handshake.
    func testLateControlFromOldSourceCannotReleaseNewSession() throws {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        _ = bridge.simulateConnectForTesting()
        let firstProxy = try XCTUnwrap(bridge.callbackProxyForTesting())
        let secondAttempt = bridge.simulateReconnectSamePeripheralForTesting()
        bridge.simulateCapabilitiesRequestedForTesting()
        _ = bridge.beginSimulatedSessionForTesting()

        // STREAM_STOP is 0x00. If the old proxy were routed by the live
        // generation, it would release this attempt-2 session.
        firstProxy.deliverForTesting(.control(Data([0x00])))

        XCTAssertTrue(bridge.isSessionLive, "stale control must not release the live session")
        XCTAssertTrue(bridge.isAttemptActiveForTesting(secondAttempt))
    }

    /// CBCentralManagerDelegate callbacks do not carry an attempt id and a
    /// reused CBPeripheral can make an object-state lookup look valid. The
    /// actual production central delegate proxy captures the source attempt;
    /// an old didConnect and didDisconnect must both be rejected after the
    /// replacement has connected.
    func testLateCentralConnectAndDisconnectFromOldSourceCannotInvalidateReplacement() {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        defer { bridge.configureForTesting() }

        let firstAttempt = bridge.simulateConnectForTesting()
        let firstProxy = bridge.centralCallbackProxyForTesting(attempt: firstAttempt)
        let secondAttempt = bridge.simulateReconnectSamePeripheralForTesting()
        let secondProxy = bridge.centralCallbackProxyForTesting(attempt: secondAttempt)

        // The replacement reaches the connected phase through the same route
        // that the real central delegate proxy calls.
        secondProxy.deliverForTesting(.didConnect)
        XCTAssertTrue(bridge.isCentralAttemptActiveForTesting(secondAttempt))

        // These are source events from the retired manager, not observations
        // of the replacement peripheral's mutable state.
        firstProxy.deliverForTesting(.didConnect)
        firstProxy.deliverForTesting(.didFailToConnect)
        firstProxy.deliverForTesting(.didDisconnect)

        XCTAssertTrue(
            bridge.isCentralAttemptActiveForTesting(secondAttempt),
            "late central events from the retired manager must not tear down the replacement"
        )
    }
}
