import AVFoundation
import CoreBluetooth
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
private final class RemoteMicCentralTransportStats {
    var stopScanCount = 0
    var scanCount = 0
    var connectCount = 0
    var cancelCount = 0
    var deinitCount = 0
}

private final class WeakObjectBox<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object) {
        self.value = value
    }
}

private final class RemoteMicCentralTransportFake: XiaomiRemoteMicCentralTransport {
    let identity: AnyObject = NSObject()
    let delegateProxy: XiaomiRemoteMicCentralDelegateProxy
    var state: CBManagerState = .poweredOn
    private let stats: RemoteMicCentralTransportStats

    init(bridge: XiaomiRemoteMicBridge, stats: RemoteMicCentralTransportStats) {
        self.stats = stats
        let proxy = XiaomiRemoteMicCentralDelegateProxy(bridge: bridge)
        delegateProxy = proxy
        proxy.bindManagerIdentity(identity)
    }

    deinit {
        stats.deinitCount += 1
    }

    func stopScan() {
        stats.stopScanCount += 1
    }

    func scanForPeripherals(withServices services: [CBUUID], options: [String: Any]?) {
        stats.scanCount += 1
    }

    func connect(to peripheral: AnyObject) {
        stats.connectCount += 1
        delegateProxy.bindPeripheralIdentity(peripheral)
    }

    func cancel(peripheral: AnyObject) {
        stats.cancelCount += 1
    }
}

@MainActor
private func waitForProductionScanFence() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

@MainActor
final class RemoteMicCallbackRoutingTests: XCTestCase {
    private func makeCentralGateFixture() throws -> (
        bridge: XiaomiRemoteMicBridge,
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        attempt: UInt64
    ) {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        let stats = RemoteMicCentralTransportStats()
        bridge.installCentralTransportFactoryForTesting { [weak bridge] in
            guard let bridge else {
                preconditionFailure("central gate fixture outlived its bridge")
            }
            RemoteMicCentralTransportFake(
                bridge: bridge,
                stats: stats
            )
        }
        bridge.activate()
        bridge.simulateCentralStateForTesting(.poweredOn)
        let peripheralIdentity = NSObject()
        let attempt = try XCTUnwrap(
            bridge.simulateCentralDiscoveryForTesting(peripheralIdentity: peripheralIdentity)
        )
        let managerIdentity = try XCTUnwrap(bridge.centralTransportForTesting()?.identity)
        return (bridge, managerIdentity, peripheralIdentity, attempt)
    }

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

    /// The route is intentionally given exactly one wrong identity at a time.
    /// If the manager gate is removed, this same-attempt/same-peripheral
    /// failure callback would retire the active connection.
    func testCentralManagerIdentityGateRejectsWrongManager() throws {
        let fixture = try makeCentralGateFixture()
        defer { fixture.bridge.configureForTesting() }

        fixture.bridge.routeCentralCallbackForTesting(
            .didFailToConnect,
            attempt: fixture.attempt,
            managerIdentity: NSObject(),
            peripheralIdentity: fixture.peripheralIdentity
        )

        XCTAssertTrue(
            fixture.bridge.isCentralAttemptActiveForTesting(fixture.attempt),
            "manager identity gate must reject a same-attempt callback from another manager"
        )
    }

    /// The manager and attempt are correct here; only the peripheral identity
    /// is wrong. This catches a route that trusts the reused CBPeripheral slot.
    func testCentralPeripheralIdentityGateRejectsWrongPeripheral() throws {
        let fixture = try makeCentralGateFixture()
        defer { fixture.bridge.configureForTesting() }

        fixture.bridge.routeCentralCallbackForTesting(
            .didFailToConnect,
            attempt: fixture.attempt,
            managerIdentity: fixture.managerIdentity,
            peripheralIdentity: NSObject()
        )

        XCTAssertTrue(
            fixture.bridge.isCentralAttemptActiveForTesting(fixture.attempt),
            "peripheral identity gate must reject a same-attempt callback from another peripheral"
        )
    }

    /// The manager and peripheral are correct here; only the proxy source
    /// attempt is stale. The mutation recipe removes all source-attempt
    /// comparisons together so this test cannot be masked by a second gate.
    func testCentralAttemptIdentityGateRejectsWrongAttempt() throws {
        let fixture = try makeCentralGateFixture()
        defer { fixture.bridge.configureForTesting() }

        fixture.bridge.routeCentralCallbackForTesting(
            .didFailToConnect,
            attempt: fixture.attempt &+ 1,
            managerIdentity: fixture.managerIdentity,
            peripheralIdentity: fixture.peripheralIdentity
        )

        XCTAssertTrue(
            fixture.bridge.isCentralAttemptActiveForTesting(fixture.attempt),
            "source attempt gate must reject a stale attempt from the active manager and peripheral"
        )
    }

    /// The real activate -> transport initializer -> discover/connect path is
    /// used here. A pending connection is cancelled even though no connected
    /// state has been observed; immediate reactivation stays behind the old
    /// manager's terminal callback; and the old manager/proxy context is
    /// released only after that callback.
    func testProductionCentralRetirementCancelsPendingAndDefersFastReactivation() throws {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        defer { bridge.configureForTesting() }

        var transportStats: [RemoteMicCentralTransportStats] = []
        var weakTransports: [WeakObjectBox<RemoteMicCentralTransportFake>] = []
        var createdTransportCount = 0
        bridge.installCentralTransportFactoryForTesting { [weak bridge] in
            guard let bridge else {
                preconditionFailure("retirement fixture outlived its bridge")
            }
            let stats = RemoteMicCentralTransportStats()
            transportStats.append(stats)
            let transport = RemoteMicCentralTransportFake(bridge: bridge, stats: stats)
            weakTransports.append(WeakObjectBox(transport))
            createdTransportCount += 1
            return transport
        }

        bridge.activate()
        XCTAssertEqual(createdTransportCount, 1, "activate must create the production transport")
        bridge.simulateCentralStateForTesting(.poweredOn)
        XCTAssertEqual(transportStats[0].scanCount, 1)

        let firstPeripheral = NSObject()
        let firstAttempt = try XCTUnwrap(
            bridge.simulateCentralDiscoveryForTesting(peripheralIdentity: firstPeripheral)
        )
        XCTAssertEqual(bridge.attemptForCurrentPeripheralForTesting(), firstAttempt)
        var firstProxy: XiaomiRemoteMicCentralDelegateProxy? = try XCTUnwrap(
            bridge.centralTransportForTesting()?.delegateProxy
        )
        var firstPeripheralProxy: XiaomiRemoteMicPeripheralDelegateProxy? = try XCTUnwrap(
            bridge.callbackProxyForTesting()
        )
        let weakFirstProxy = WeakObjectBox(firstProxy!)
        let weakFirstPeripheralProxy = WeakObjectBox(firstPeripheralProxy!)
        let weakFirstManagerIdentity = WeakObjectBox(
            try XCTUnwrap(firstProxy?.sourceManagerIdentity)
        )
        XCTAssertEqual(transportStats[0].connectCount, 1)
        XCTAssertNotNil(firstProxy?.sourceManagerIdentity)
        XCTAssertNotNil(firstProxy?.sourcePeripheralIdentity)

        bridge.deactivate()
        XCTAssertEqual(transportStats[0].cancelCount, 1, "pending connect must be cancelled")
        XCTAssertTrue(bridge.isCentralQuiescingForTesting())
        XCTAssertEqual(bridge.retiredCentralContextCountForTesting(), 1)
        XCTAssertEqual(bridge.retiredPeripheralContextCountForTesting(), 1)

        // Turning the feature on again does not construct a second manager
        // while the first cancellation is still pending.
        bridge.activate()
        XCTAssertEqual(createdTransportCount, 1)
        XCTAssertTrue(bridge.isCentralQuiescingForTesting())

        // This failure event is delivered through the old production proxy. It
        // is the cancellation completion, not a Task.yield or a mutable-state
        // guess; the separate late didDisconnect below must then be harmless.
        firstProxy?.deliverForTesting(.didFailToConnect)
        XCTAssertEqual(bridge.retiredCentralContextCountForTesting(), 0)
        XCTAssertEqual(bridge.retiredPeripheralContextCountForTesting(), 0)
        XCTAssertEqual(createdTransportCount, 2, "replacement starts only after completion")
        XCTAssertNil(
            weakTransports[0].value,
            "terminal completion must release the retired transport immediately"
        )
        XCTAssertEqual(
            transportStats[0].deinitCount,
            1,
            "terminal completion must deinitialize the retired transport exactly once"
        )

        bridge.simulateCentralStateForTesting(.poweredOn)
        let secondAttempt = try XCTUnwrap(
            bridge.simulateCentralDiscoveryForTesting(peripheralIdentity: firstPeripheral)
        )
        let secondProxy = try XCTUnwrap(bridge.centralTransportForTesting()?.delegateProxy)
        secondProxy.deliverForTesting(.didConnect)
        XCTAssertTrue(bridge.isCentralAttemptActiveForTesting(secondAttempt))

        // The old source has the same peripheral identity, but a different
        // manager identity and attempt. All late old callbacks must be dropped.
        firstProxy?.deliverForTesting(.didConnect)
        firstProxy?.deliverForTesting(.didFailToConnect)
        firstProxy?.deliverForTesting(.didDisconnect)

        XCTAssertTrue(
            bridge.isCentralAttemptActiveForTesting(secondAttempt),
            "late events from the retired manager must not tear down the replacement"
        )

        // Drop every test-owned strong reference after the old source has
        // finished delivering. The weak boxes and deinit counter prove that
        // the bridge's retired containers, not the test array, owned release.
        firstProxy = nil
        firstPeripheralProxy = nil
        XCTAssertNil(weakFirstProxy.value)
        XCTAssertNil(weakFirstPeripheralProxy.value)
        XCTAssertNil(weakFirstManagerIdentity.value)
    }

    /// A scan-only retirement has no peripheral terminal callback. The main
    /// queue fence is explicit and non-blocking: the old transport remains
    /// retained until the injected fence completion, and fast reactivation is
    /// held behind it.
    func testScanRetirementUsesNonBlockingFenceBeforeReactivation() async {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        defer { bridge.configureForTesting() }

        var transportStats: [RemoteMicCentralTransportStats] = []
        var weakFirstTransport: WeakObjectBox<RemoteMicCentralTransportFake>?
        var createdTransportCount = 0
        bridge.installCentralTransportFactoryForTesting { [weak bridge] in
            guard let bridge else {
                preconditionFailure("scan-fence fixture outlived its bridge")
            }
            let stats = RemoteMicCentralTransportStats()
            transportStats.append(stats)
            let transport = RemoteMicCentralTransportFake(bridge: bridge, stats: stats)
            if weakFirstTransport == nil {
                weakFirstTransport = WeakObjectBox(transport)
            }
            createdTransportCount += 1
            return transport
        }

        bridge.activate()
        bridge.simulateCentralStateForTesting(.poweredOn)
        XCTAssertEqual(transportStats[0].scanCount, 1)

        bridge.deactivate()
        XCTAssertTrue(bridge.isCentralQuiescingForTesting())
        XCTAssertEqual(bridge.retiredCentralContextCountForTesting(), 1)

        bridge.activate()
        XCTAssertEqual(createdTransportCount, 1)
        await waitForProductionScanFence()

        XCTAssertFalse(bridge.isCentralQuiescingForTesting())
        XCTAssertEqual(createdTransportCount, 2)
        XCTAssertNil(weakFirstTransport?.value)
        XCTAssertEqual(transportStats[0].deinitCount, 1)
    }
}
