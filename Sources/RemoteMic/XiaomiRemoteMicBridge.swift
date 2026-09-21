import CoreBluetooth
import Foundation

enum RemoteMicBridgeState: Equatable {
    case idle
    case unsupported
    case unauthorized
    case scanning
    case connecting
    case ready(deviceName: String)
    case failed(reason: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .idle: return L("remote_mic.state.idle")
        case .unsupported: return L("remote_mic.state.unsupported")
        case .unauthorized: return L("remote_mic.state.unauthorized")
        case .scanning: return L("remote_mic.state.scanning")
        case .connecting: return L("remote_mic.state.connecting")
        case let .ready(deviceName): return String(format: L("remote_mic.state.ready"), deviceName)
        case let .failed(reason): return String(format: L("remote_mic.state.failed"), reason)
        }
    }
}

/// The two CoreBluetooth notifications the ATVV handshake needs before the host
/// may request capabilities.
enum RemoteMicSubscription: Hashable {
    case audio
    case control
}

/// The delegate callbacks below do not contain a CoreBluetooth connection id.
/// A proxy is therefore installed for each connection lifecycle and captures
/// the attempt at the point where CoreBluetooth is wired to the bridge. The
/// bridge never looks up an attempt from the current peripheral when routing a
/// callback; the proxy is the callback's source envelope.
enum XiaomiRemoteMicTestCallback: Equatable {
    case disconnect
    case control(Data)
    case audio(Data)
}

/// Central callbacks have the same source problem as peripheral callbacks:
/// CoreBluetooth supplies the peripheral object, but no connection-attempt id.
/// The production central delegate proxy captures the id when a discovered
/// peripheral is connected. Tests use the same proxy route to deliver a late
/// event from an older central lifecycle.
enum XiaomiRemoteMicCentralTestCallback: Equatable {
    case didConnect
    case didFailToConnect
    case didDisconnect
}

final class XiaomiRemoteMicPeripheralDelegateProxy: NSObject, CBPeripheralDelegate {
    weak var bridge: XiaomiRemoteMicBridge?
    let attempt: UInt64

    init(bridge: XiaomiRemoteMicBridge, attempt: UInt64) {
        self.bridge = bridge
        self.attempt = attempt
        super.init()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        bridge?.routeDidDiscoverServices(peripheral, error: error, attempt: attempt)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        bridge?.routeDidDiscoverCharacteristics(
            peripheral,
            service: service,
            error: error,
            attempt: attempt
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        bridge?.routeDidUpdateNotificationState(
            peripheral,
            characteristic: characteristic,
            error: error,
            attempt: attempt
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        bridge?.routeDidUpdateValue(
            peripheral,
            characteristic: characteristic,
            error: error,
            attempt: attempt
        )
    }

    /// Drives the same bridge route as the CoreBluetooth delegate methods, but
    /// without manufacturing CoreBluetooth objects. This is the test entry for
    /// a callback that was raised by this particular lifecycle proxy.
    func deliverForTesting(_ callback: XiaomiRemoteMicTestCallback) {
        bridge?.routeTestCallback(callback, attempt: attempt)
    }
}

/// One central manager is used for one connection lifecycle. A
/// `CBCentralManagerDelegate` callback has no source id, so reusing a manager
/// would make a late callback indistinguishable from the replacement attempt.
/// Keeping this proxy with the manager gives every callback the lifecycle that
/// actually owned that manager. The scan phase is unbound; it is bound exactly
/// when `didDiscover` starts the connection.
final class XiaomiRemoteMicCentralDelegateProxy: NSObject, CBCentralManagerDelegate {
    weak var bridge: XiaomiRemoteMicBridge?
    private(set) var attempt: UInt64?
    private(set) var sourceManagerIdentity: AnyObject?
    private(set) var sourcePeripheralIdentity: AnyObject?

    init(bridge: XiaomiRemoteMicBridge) {
        self.bridge = bridge
        super.init()
    }

    func bind(to attempt: UInt64) {
        guard self.attempt == nil else { return }
        self.attempt = attempt
    }

    func bindManagerIdentity(_ identity: AnyObject) {
        guard sourceManagerIdentity == nil else { return }
        sourceManagerIdentity = identity
    }

    func bindPeripheralIdentity(_ identity: AnyObject) {
        sourcePeripheralIdentity = identity
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bindManagerIdentity(central)
        bridge?.routeCentralManagerDidUpdateState(
            managerIdentity: central,
            managerState: central.state,
            sourceAttempt: attempt
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidDiscover(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI,
            sourceAttempt: attempt
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            sourceAttempt: attempt
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidFailToConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: attempt
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidDisconnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: attempt
        )
    }

    /// Test-only entry that uses the same source-bound route as the delegate
    /// methods above, without manufacturing CoreBluetooth objects.
    func deliverForTesting(_ callback: XiaomiRemoteMicCentralTestCallback) {
        guard let attempt,
              let sourceManagerIdentity,
              let sourcePeripheralIdentity else { return }
        bridge?.routeCentralCallbackForTesting(
            callback,
            attempt: attempt,
            managerIdentity: sourceManagerIdentity,
            peripheralIdentity: sourcePeripheralIdentity
        )
    }
}

/// The bridge owns one transport for one central lifecycle. Keeping the
/// transport behind this seam lets tests exercise the production initializer,
/// strong manager/proxy ownership, identity gates, and cancellation completion
/// without manufacturing a CoreBluetooth object.
protocol XiaomiRemoteMicCentralTransport: AnyObject {
    var identity: AnyObject { get }
    var delegateProxy: XiaomiRemoteMicCentralDelegateProxy { get }
    var state: CBManagerState { get }

    func stopScan()
    func scanForPeripherals(withServices services: [CBUUID], options: [String: Any]?)
    func connect(to peripheral: AnyObject)
    func cancel(peripheral: AnyObject)
}

/// Production transport. The manager and its weak delegate are held together
/// so an old manager can still deliver a terminal callback to its old proxy
/// while retirement is waiting for cancellation to complete.
final class XiaomiRemoteMicCoreBluetoothCentralTransport: XiaomiRemoteMicCentralTransport {
    let manager: CBCentralManager
    let delegateProxy: XiaomiRemoteMicCentralDelegateProxy

    var identity: AnyObject { manager }
    var state: CBManagerState { manager.state }

    init(bridge: XiaomiRemoteMicBridge) {
        let proxy = XiaomiRemoteMicCentralDelegateProxy(bridge: bridge)
        delegateProxy = proxy
        manager = CBCentralManager(
            delegate: proxy,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        proxy.bindManagerIdentity(manager)
    }

    func stopScan() {
        manager.stopScan()
    }

    func scanForPeripherals(withServices services: [CBUUID], options: [String: Any]?) {
        manager.scanForPeripherals(withServices: services, options: options)
    }

    func connect(to peripheral: AnyObject) {
        guard let peripheral = peripheral as? CBPeripheral else { return }
        manager.connect(peripheral, options: nil)
    }

    func cancel(peripheral: AnyObject) {
        guard let peripheral = peripheral as? CBPeripheral else { return }
        manager.cancelPeripheralConnection(peripheral)
    }
}

/// CoreBluetooth keeps a peripheral's delegate weak. Keep the old peripheral
/// and its source proxy together until the central's cancellation callback has
/// arrived; otherwise a queued didDisconnect/didFail event can disappear or be
/// delivered to a replacement lifecycle.
private final class XiaomiRemoteMicPeripheralContext {
    let identity: AnyObject
    let peripheral: CBPeripheral?
    let delegateProxy: XiaomiRemoteMicPeripheralDelegateProxy

    init(
        identity: AnyObject,
        peripheral: CBPeripheral?,
        delegateProxy: XiaomiRemoteMicPeripheralDelegateProxy
    ) {
        self.identity = identity
        self.peripheral = peripheral
        self.delegateProxy = delegateProxy
    }
}

private enum XiaomiRemoteMicCentralLifecycle: Equatable {
    case idle
    case scanning(UInt64)
    case connecting(UInt64)
    case connected(UInt64)
    case quiescing(UInt64)

    var attempt: UInt64? {
        switch self {
        case .idle: return nil
        case let .scanning(attempt), let .connecting(attempt),
             let .connected(attempt), let .quiescing(attempt):
            return attempt
        }
    }
}

/// CoreBluetooth central that connects a Xiaomi Bluetooth Remote 2 Pro over the
/// ATVV profile and turns its audio notifications into PCM frames.
///
/// The remote keeps its own microphone stream private to the ATVV channel; this
/// bridge decodes that stream in-process, so Utter needs neither the vendor's
/// virtual audio driver nor a second application.
///
/// Handshake order is enforced: discover characteristics, subscribe to both the
/// audio and control notifications, wait for CoreBluetooth to confirm every
/// subscription, and only then send `GET_CAPABILITIES`. A connection or
/// initialization that stalls past its timeout is failed and retried instead of
/// leaving the UI in `.connecting` forever.
final class XiaomiRemoteMicBridge: NSObject, ObservableObject {
    static let shared = XiaomiRemoteMicBridge()

    /// How long a connection, or the initialization sequence after it, may take
    /// before the attempt is failed and retried.
    static let connectionTimeout: TimeInterval = 10
    static let initializationTimeout: TimeInterval = 8

    @Published private(set) var state: RemoteMicBridgeState = .idle

    /// Decoded 16 kHz mono samples while a voice session is streaming.
    var onSamples: (([Int16]) -> Void)?
    /// Fired when the remote stops streaming, including unexpected disconnects.
    var onStreamStopped: (() -> Void)?
    /// Fired when the remote's voice key starts a voice session, with the latch
    /// token the caller must commit when its asynchronous start completes. The
    /// remote signals this on the ATVV control channel (`AUDIO_START` for the
    /// no-`START_SEARCH` interaction model), so the voice key drives Utter's
    /// recording without a separate HID key remap or an Input Monitoring
    /// permission.
    var onVoiceKeyPressed: ((UInt64) -> Void)?
    /// Fired when the remote's voice key ends the session. The caller stops or
    /// cancels its in-flight start for the current latch.
    var onVoiceKeyReleased: (() -> Void)?

    private var centralTransport: XiaomiRemoteMicCentralTransport?
    private var centralTransportFactory: (() -> XiaomiRemoteMicCentralTransport)?
    /// Retired transports stay alive until their terminal central callback (or
    /// a scan queue fence) completes. Keying by manager identity prevents a
    /// still-pending old context from being evicted by an arbitrary FIFO cap.
    private var retiredCentralContexts: [ObjectIdentifier: XiaomiRemoteMicCentralTransport] = [:]
    private var retiredPeripheralContexts: [ObjectIdentifier: XiaomiRemoteMicPeripheralContext] = [:]
    private var pendingCentralRetirement: (
        identity: AnyObject,
        attempt: UInt64,
        peripheralKey: ObjectIdentifier?
    )?
    private var centralLifecycle: XiaomiRemoteMicCentralLifecycle = .idle
    private var scanRequestedWhileQuiescing = false
    private var peripheral: CBPeripheral?
    private var peripheralIdentity: AnyObject?
    /// Attempt of the currently active connection lifecycle. Callback routes
    /// compare their proxy-captured source against this value; no route
    /// derives an old callback's source by looking at the current peripheral.
    private var activeConnectionAttempt: UInt64?
    /// Retained so CoreBluetooth can call the source-bound proxy. An old proxy
    /// may still deliver a queued callback, but its captured attempt will fail
    /// the bridge's current-lifecycle gate.
    private var peripheralCallbackProxy: XiaomiRemoteMicPeripheralDelegateProxy?
    private var transmitCharacteristic: CBCharacteristic?
    private var audioCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var handshake = RemoteMicHandshake()

    private var capabilities = RemoteMicCapabilities.default
    private var microphoneOpened = false
    /// Latches the voice-key session synchronously, so a release or disconnect
    /// that arrives while the pipeline is still starting cancels the pending
    /// start instead of being ignored.
    private var session = RemoteMicSession()
    /// Audio that arrives before the capture pipeline is ready, so the opening
    /// word is not clipped.
    private var preRoll = RemoteMicPreRoll()
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isActive = false

    /// Monotonic attempt counter. Both peripheral and central callbacks carry
    /// their source attempt through a lifecycle proxy. CoreBluetooth itself
    /// supplies no attempt id; the proxy is the app-owned source envelope.
    private var generation: UInt64 = 0

    private var accumulator = RemoteMicFrameAccumulator()
    private var decoder = RemoteMicADPCMDecoder()
    private var pendingSync: (predictor: Int, stepIndex: Int)?

    private var serviceUUID: CBUUID { CBUUID(string: RemoteMicProtocol.serviceUUID) }

    // MARK: - Lifecycle

    func activate() {
        guard !isActive else { return }
        isActive = true
        reconnectAttempts = 0
        guard centralTransport == nil else {
            beginScan()
            return
        }
        if case .quiescing = centralLifecycle {
            // `deactivate()` has already issued cancellation. Do not create a
            // new manager until the old context reports terminal completion.
            scanRequestedWhileQuiescing = true
            return
        }
        installCentralTransport()
    }

    func deactivate() {
        isActive = false
        // Closing the feature must end a live session, not leave Utter recording.
        let wasLive = session.invalidate()
        if wasLive {
            onStreamStopped?()
            onVoiceKeyReleased?()
        }
        cancelReconnect()
        cancelTimeout()
        generation &+= 1
        closeMicrophoneIfNeeded()
        resetStream()
        retireCurrentCentral()
        resetPeripheral()
        state = .idle
    }

    /// Commits the latched voice-key session to the capture pipeline and returns
    /// any audio buffered before it was ready, in order.
    ///
    /// `token` is the latch the caller observed when it started; if the session
    /// was released or superseded meanwhile this returns `nil`, and the caller
    /// must not begin recording.
    func beginCapture(token: UInt64) -> [Int16]? {
        if !isActive { activate() }
        guard session.commitStart(token: token) else { return nil }
        guard peripheral?.state == .connected, handshake.isReady else {
            // Not usable yet: drop the latched session so a later readiness does
            // not open the remote microphone for a session that fell back.
            _ = session.release()
            preRoll.reset()
            return nil
        }
        if !microphoneOpened { openMicrophoneIfNeeded() }
        let buffered = preRoll.drain().flatMap { $0 }
        return buffered
    }

    /// True while a voice-key session is latched or recording.
    var isSessionLive: Bool { session.isLive }

    /// The latch of the current voice-key session, or nil when idle.
    var currentSessionToken: UInt64? { session.isLive ? session.generation : nil }

    /// True while `token` is still the live voice-key session. Used by the
    /// pipeline to abort a start whose key was released while the model loaded.
    static func isSessionCurrent(_ token: UInt64) -> Bool {
        shared.session.isLive && shared.session.generation == token
    }

    /// Test-only: latch a session without a real remote, so tests can drive the
    /// pipeline's post-load check through the real bridge predicate.
    func beginSimulatedSessionForTesting() -> UInt64 {
        session.press()
    }

    /// Test-only: release the simulated session.
    @discardableResult
    func endSimulatedSessionForTesting() -> Bool {
        session.release()
    }

    // MARK: - Test-only routing seams

    /// Test-only: reset to a clean state for routing tests.
    func configureForTesting() {
        cancelReconnect()
        cancelTimeout()
        if let transport = centralTransport {
            transport.stopScan()
            if let peripheralIdentity { transport.cancel(peripheral: peripheralIdentity) }
        }
        centralTransport = nil
        pendingCentralRetirement = nil
        for context in retiredPeripheralContexts.values {
            context.peripheral?.delegate = nil
        }
        retiredCentralContexts.removeAll()
        retiredPeripheralContexts.removeAll()
        centralLifecycle = .idle
        scanRequestedWhileQuiescing = false
        isActive = false
        resetPeripheral()
        handshake.reset()
        generation = 0
        state = .idle
    }

    /// Test-only: the factory is consumed by `activate()`/`installCentralTransport()`
    /// exactly like the production CoreBluetooth initializer. It is not a
    /// proxy-only injection seam.
    func installCentralTransportFactoryForTesting(
        _ factory: @escaping () -> XiaomiRemoteMicCentralTransport
    ) {
        centralTransportFactory = factory
    }

    /// Test-only: the currently held production transport, including its
    /// non-nil manager identity and delegate proxy.
    func centralTransportForTesting() -> XiaomiRemoteMicCentralTransport? {
        centralTransport
    }

    /// Test-only: drive the same central state route with a non-nil manager
    /// identity supplied by the production-created transport.
    func simulateCentralStateForTesting(_ state: CBManagerState) {
        guard let transport = centralTransport else { return }
        routeCentralManagerDidUpdateState(
            managerIdentity: transport.identity,
            managerState: state,
            sourceAttempt: transport.delegateProxy.attempt
        )
    }

    /// Test-only: drive discovery through the production route with a
    /// non-nil peripheral identity. Returns the attempt bound by discovery.
    @discardableResult
    func simulateCentralDiscoveryForTesting(peripheralIdentity: AnyObject) -> UInt64? {
        guard let transport = centralTransport else { return nil }
        transport.delegateProxy.bindPeripheralIdentity(peripheralIdentity)
        routeCentralDidDiscover(
            managerIdentity: transport.identity,
            peripheralIdentity: peripheralIdentity,
            peripheral: nil,
            sourceAttempt: transport.delegateProxy.attempt
        )
        return activeConnectionAttempt
    }

    /// Test-only: explicitly deliver the cancellation completion of the held
    /// transport. Production gets this signal from didDisconnect/didFail or a
    /// main-queue scan fence; tests inject it deterministically.
    func completeCentralRetirementForTesting() {
        guard let pending = pendingCentralRetirement else { return }
        finishCentralRetirement(managerIdentity: pending.identity, attempt: pending.attempt)
    }

    /// Test-only: evidence for the ownership contract: a retired context is
    /// retained until completion, then released.
    func retiredCentralContextCountForTesting() -> Int {
        retiredCentralContexts.count
    }

    /// Test-only: the old peripheral delegate/proxy is held through terminal
    /// cancellation, then released with the retired central context.
    func retiredPeripheralContextCountForTesting() -> Int {
        retiredPeripheralContexts.count
    }

    /// Test-only: the production manager may not be created while this gate is
    /// pending, even when the feature is turned on again immediately.
    func isCentralQuiescingForTesting() -> Bool {
        if case .quiescing = centralLifecycle { return true }
        return false
    }

    /// Test-only: simulate a connect and return the attempt it bound.
    @discardableResult
    func simulateConnectForTesting() -> UInt64 {
        generation &+= 1
        let attempt = generation
        beginPeripheralAttempt(attempt)
        centralLifecycle = .connecting(attempt)
        state = .connecting
        return attempt
    }

    /// Test-only: simulate a reconnect on the same peripheral object. The new
    /// lifecycle gets a new source proxy; callers can retain the old proxy and
    /// deliver a late event through the production route.
    @discardableResult
    func simulateReconnectSamePeripheralForTesting() -> UInt64 {
        simulateConnectForTesting()
    }

    /// Test-only: the attempt currently accepted for the lifecycle.
    func attemptForCurrentPeripheralForTesting() -> UInt64? {
        activeConnectionAttempt
    }

    /// Test-only: retain the source envelope for a simulated lifecycle.
    func callbackProxyForTesting() -> XiaomiRemoteMicPeripheralDelegateProxy? {
        peripheralCallbackProxy
    }

    /// Test-only: whether the lifecycle is still installed after a late event.
    func isAttemptActiveForTesting(_ attempt: UInt64) -> Bool {
        activeConnectionAttempt == attempt && peripheralCallbackProxy?.attempt == attempt
    }

    /// Test-only: whether the source-bound central lifecycle is still current.
    func isCentralAttemptActiveForTesting(_ attempt: UInt64) -> Bool {
        centralLifecycle.attempt == attempt
            && activeConnectionAttempt == attempt
            && handshake.accepts(attempt)
    }

    /// Test-only: whether the handshake still tracks `attempt`.
    func acceptsAttemptForTesting(_ attempt: UInt64) -> Bool {
        handshake.accepts(attempt)
    }

    /// Test-only: send the capability request for the current attempt.
    func simulateCapabilitiesRequestedForTesting() {
        handshake.markCapabilitiesRequested()
    }

    func endCapture() {
        // Close exactly once, whatever the phase: a release during `starting`
        // must still close a microphone this bridge may have opened, and must
        // not leave `microphoneOpened` set for the next attempt.
        let wasLive = session.release()
        if microphoneOpened || wasLive {
            closeMicrophoneIfNeeded()
        }
        if !session.isLive {
            preRoll.reset()
            accumulator.reset()
            pendingSync = nil
            decoder.reset()
        }
    }

    // MARK: - Control

    private func openMicrophoneIfNeeded() {
        guard !microphoneOpened else { return }
        let command = RemoteMicProtocol.microphoneOpen(
            version: capabilities.version,
            codec: capabilities.selectedCodec
        )
        guard write(command) else { return }
        microphoneOpened = true
    }

    private func closeMicrophoneIfNeeded() {
        guard microphoneOpened else { return }
        _ = write(RemoteMicProtocol.microphoneClose(
            version: capabilities.version,
            sessionID: 0
        ))
        microphoneOpened = false
    }

    private func write(_ data: Data) -> Bool {
        guard let peripheral, let transmitCharacteristic else { return false }
        let type: CBCharacteristicWriteType =
            transmitCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: transmitCharacteristic, type: type)
        return true
    }

    private func resetStream() {
        preRoll.reset()
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
    }

    // MARK: - Scanning and connection

    private func beginScan() {
        guard isActive else { return }
        switch centralLifecycle {
        case .quiescing:
            // A replacement transport is not created until the old transport
            // reports terminal cancellation (or the scan fence completes).
            scanRequestedWhileQuiescing = true
            return
        case .scanning(_), .connecting(_), .connected(_):
            return
        case .idle:
            break
        }
        guard let transport = centralTransport else {
            installCentralTransport()
            return
        }
        guard transport.state == .poweredOn else { return }
        generation &+= 1
        resetPeripheral()
        resetStream()
        handshake.reset()
        capabilities = .default
        centralLifecycle = .scanning(generation)
        state = .scanning
        transport.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Creates the central transport through the same factory used by the
    /// production CoreBluetooth initializer. A transport is never reused after
    /// its connection is retired, because its delegate callbacks otherwise
    /// carry no source id.
    private func installCentralTransport() {
        guard centralTransport == nil else { return }
        let transport = centralTransportFactory?()
            ?? XiaomiRemoteMicCoreBluetoothCentralTransport(bridge: self)
        transport.delegateProxy.bindManagerIdentity(transport.identity)
        centralTransport = transport
    }

    /// Retires the current central transport. A pending or connected
    /// peripheral is always passed to `cancel`; CoreBluetooth documents that
    /// this cancels pending as well as active local connections. The old
    /// manager/proxy remains held until didDisconnect/didFail, while a scan-only
    /// transport uses an explicit main-queue fence.
    private func retireCurrentCentral() {
        let retiredAttempt = centralLifecycle.attempt ?? generation
        guard let transport = centralTransport else {
            // A second deactivate must not turn a still-quiescing lifecycle
            // back into idle and thereby permit a replacement manager early.
            guard pendingCentralRetirement == nil else { return }
            if centralLifecycle != .idle { centralLifecycle = .idle }
            return
        }
        centralLifecycle = .quiescing(retiredAttempt)
        scanRequestedWhileQuiescing = false
        let managerIdentity = transport.identity
        let peripheralKey: ObjectIdentifier?
        if let peripheralIdentity, let peripheralCallbackProxy {
            let key = ObjectIdentifier(peripheralIdentity)
            retiredPeripheralContexts[key] = XiaomiRemoteMicPeripheralContext(
                identity: peripheralIdentity,
                peripheral: peripheral,
                delegateProxy: peripheralCallbackProxy
            )
            peripheralKey = key
        } else {
            peripheralKey = nil
        }
        retiredCentralContexts[ObjectIdentifier(managerIdentity)] = transport
        pendingCentralRetirement = (managerIdentity, retiredAttempt, peripheralKey)
        centralTransport = nil

        transport.stopScan()
        if let peripheralIdentity {
            // Do not gate cancellation on CBPeripheral.state: a connecting
            // peripheral is a pending local connection and must be cancelled.
            transport.cancel(peripheral: peripheralIdentity)
        } else {
            scheduleCentralRetirementFence(
                managerIdentity: managerIdentity,
                attempt: retiredAttempt
            )
        }
    }

    /// A scan has no didDisconnect/didFail callback. Since the manager was
    /// created with `.main`, enqueueing this completion on the same queue is the
    /// explicit scan retirement boundary. Connection retirement uses its
    /// terminal central callback instead.
    private func scheduleCentralRetirementFence(managerIdentity: AnyObject, attempt: UInt64) {
        let managerKey = ObjectIdentifier(managerIdentity)
        DispatchQueue.main.async { [weak self] in
            self?.finishCentralRetirement(managerKey: managerKey, attempt: attempt)
        }
    }

    private func finishCentralRetirement(managerIdentity: AnyObject, attempt: UInt64) {
        finishCentralRetirement(managerKey: ObjectIdentifier(managerIdentity), attempt: attempt)
    }

    private func finishCentralRetirement(managerKey: ObjectIdentifier, attempt: UInt64) {
        guard let pending = pendingCentralRetirement,
              pending.attempt == attempt,
              ObjectIdentifier(pending.identity) == managerKey else { return }
        let managerIdentity = pending.identity
        pendingCentralRetirement = nil
        retiredCentralContexts.removeValue(forKey: ObjectIdentifier(managerIdentity))
        if let peripheralKey = pending.peripheralKey,
           let context = retiredPeripheralContexts.removeValue(forKey: peripheralKey) {
            context.peripheral?.delegate = nil
        }
        centralLifecycle = .idle
        guard isActive, scanRequestedWhileQuiescing else { return }
        scanRequestedWhileQuiescing = false
        beginScan()
    }

    private func resetPeripheral() {
        // A retired context owns the old peripheral/proxy until the central
        // terminal callback. For an ordinary reset there is no such context,
        // so detach immediately.
        if let peripheralIdentity,
           retiredPeripheralContexts[ObjectIdentifier(peripheralIdentity)] == nil {
            peripheral?.delegate = nil
        }
        peripheral = nil
        peripheralIdentity = nil
        activeConnectionAttempt = nil
        peripheralCallbackProxy = nil
        transmitCharacteristic = nil
        audioCharacteristic = nil
        controlCharacteristic = nil
    }

    /// Starts a new peripheral lifecycle and installs the source-bound route.
    /// CoreBluetooth itself does not expose the attempt id on delegate events;
    /// this proxy is the lifecycle boundary that supplies it.
    private func beginPeripheralAttempt(
        _ attempt: UInt64,
        peripheral: CBPeripheral? = nil,
        peripheralIdentity: AnyObject? = nil
    ) {
        activeConnectionAttempt = attempt
        handshake.beginAttempt(attempt)
        let proxy = XiaomiRemoteMicPeripheralDelegateProxy(bridge: self, attempt: attempt)
        peripheralCallbackProxy = proxy
        self.peripheralIdentity = peripheralIdentity ?? peripheral
        if let peripheral {
            self.peripheral = peripheral
            peripheral.delegate = proxy
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Fails the current attempt after `seconds` unless `isSatisfied` says the
    /// step completed. Runs on the main actor so the check races nothing.
    private func startTimeout(
        seconds: TimeInterval,
        generation expected: UInt64,
        reason: @escaping @autoclosure () -> String,
        isSatisfied: @escaping () -> Bool
    ) {
        cancelTimeout()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled, self.generation == expected else { return }
            guard !isSatisfied() else { return }
            self.failAttempt(reason: reason())
        }
    }

    private func failAttempt(reason: String) {
        state = .failed(reason: reason)
        resetStream()
        closeMicrophoneIfNeeded()
        retireCurrentCentral()
        resetPeripheral()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isActive else { return }
        cancelReconnect()
        reconnectAttempts += 1
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempts, 5))))
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.beginScan()
        }
    }

    fileprivate func handleDisconnect() {
        if session.invalidate() {
            onStreamStopped?()
            onVoiceKeyReleased?()
        }
        resetStream()
        handshake.reset()
        microphoneOpened = false
        cancelTimeout()
        retireCurrentCentral()
        resetPeripheral()
        if isActive { scheduleReconnect() }
    }

    // MARK: - Control protocol

    fileprivate func handleControl(_ data: Data, attempt: UInt64) {
        guard handshake.accepts(attempt) else { return }
        let bytes = Array(data)
        guard let opcode = bytes.first.flatMap(RemoteMicControlOpcode.init(rawValue:)) else { return }

        switch opcode {
        case .capabilities:
            guard let parsed = RemoteMicCapabilities.parse(data) else {
                failAttempt(reason: L("remote_mic.error.invalid_response"))
                return
            }
            capabilities = parsed
            guard RemoteMicProtocol.supportsAudio(sampleRate: parsed.sampleRate) else {
                failAttempt(reason: L("remote_mic.error.unsupported_codec"))
                return
            }
            guard handshake.confirmCapabilities(parsed) else {
                failAttempt(reason: L("remote_mic.error.unsupported_codec"))
                return
            }
            cancelTimeout()
            reconnectAttempts = 0
            state = .ready(deviceName: peripheral?.name ?? "MI RC")
            if session.isLive { openMicrophoneIfNeeded() }
        case .startSearch:
            guard handshake.isReady, isActive else { return }
            // `START_SEARCH` (0x08) is the device announcing itself, not a
            // host-side microphone open. A device-driven session needs no host
            // request, so keep the channel open; the session latches on
            // AUDIO_START so a short press is not lost.
            openMicrophoneIfNeeded()
        case .streamStart:
            guard handshake.isReady, isActive else { return }
            if bytes.count >= 3 {
                let codec = bytes[2]
                capabilities.selectedCodec = codec
                capabilities.sampleRate = codec == 0x02 ? 16_000 : 8_000
            }
            guard RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate) else {
                failAttempt(reason: L("remote_mic.error.unsupported_codec"))
                return
            }
            // Latch synchronously: the pipeline start is asynchronous, and a
            // stop or disconnect may arrive before it commits.
            let token = session.press()
            onVoiceKeyPressed?(token)
        case .streamStop:
            // Release before clearing state so endCapture can still close the
            // microphone; previously the reset ran first and made that
            // unreachable, leaving microphoneOpened set.
            let wasLive = session.release()
            preRoll.reset()
            accumulator.reset()
            pendingSync = nil
            decoder.reset()
            if wasLive { onVoiceKeyReleased?() }
        case .sync:
            guard bytes.count >= 7 else { return }
            let bits = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
            pendingSync = (Int(Int16(bitPattern: bits)), Int(bytes[6]))
            accumulator.reset()
        }
    }

    fileprivate func handleAudio(_ data: Data, attempt: UInt64) {
        guard handshake.accepts(attempt) else { return }
        guard handshake.isReady else { return }
        let frames = accumulator.append(data, frameSize: capabilities.frameSize)
        for frame in frames {
            if let pendingSync {
                decoder.reset(predictor: pendingSync.predictor, stepIndex: pendingSync.stepIndex)
                self.pendingSync = nil
            }
            let samples = RemoteMicPCM.process(
                decoder.decode(frame),
                gainDB: AppSettings.shared.remoteMicGainDB
            )
            // Route through the shared rule so the behaviour a test asserts is
            // the behaviour the bridge runs.
            switch RemoteMicAudioRouting.destination(for: session.phase) {
            case .forward:
                onSamples?(samples)
            case .preRoll:
                preRoll.append(samples)
            case .drop:
                break
            }
        }
    }

    /// Sends the capability request only once both notify subscriptions are
    /// confirmed, and only once per attempt.
    fileprivate func requestCapabilitiesIfReady() {
        guard handshake.shouldRequestCapabilities else { return }
        handshake.markCapabilitiesRequested()
        startTimeout(
            seconds: Self.initializationTimeout,
            generation: generation,
            reason: L("remote_mic.error.initialization_timeout"),
            isSatisfied: { [weak self] in self?.handshake.isReady ?? false }
        )
        _ = write(RemoteMicProtocol.getCapabilities)
    }
}

extension XiaomiRemoteMicBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // The bridge remains conformant for compatibility, but production
        // managers use XiaomiRemoteMicCentralDelegateProxy. An unbound direct
        // callback is deliberately not accepted for connection events.
        routeCentralManagerDidUpdateState(
            managerIdentity: central,
            managerState: central.state,
            sourceAttempt: nil
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        routeCentralDidDiscover(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI,
            sourceAttempt: nil
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        routeCentralDidConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            sourceAttempt: nil
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        routeCentralDidFailToConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: nil
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        routeCentralDidDisconnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: nil
        )
    }

    fileprivate func routeCentralManagerDidUpdateState(
        managerIdentity: AnyObject,
        managerState: CBManagerState,
        sourceAttempt: UInt64?
    ) {
        guard let transport = centralTransport,
              transport.identity === managerIdentity else { return }
        switch managerState {
        case .poweredOn:
            // Only the unbound scan manager may begin a scan. A callback from
            // a connection manager never restarts the lifecycle.
            if sourceAttempt == nil { beginScan() }
        case .unauthorized:
            guard sourceAttempt == nil || sourceAttempt == centralLifecycle.attempt else { return }
            cancelTimeout()
            cancelReconnect()
            self.state = .unauthorized
        case .unsupported:
            guard sourceAttempt == nil || sourceAttempt == centralLifecycle.attempt else { return }
            cancelTimeout()
            cancelReconnect()
            self.state = .unsupported
        default:
            guard sourceAttempt == nil || sourceAttempt == centralLifecycle.attempt else { return }
            cancelTimeout()
            self.state = .idle
        }
    }

    fileprivate func routeCentralDidDiscover(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber,
        sourceAttempt: UInt64?
    ) {
        guard sourceAttempt == nil,
              isActive,
              let transport = centralTransport,
              transport.identity === managerIdentity,
              self.peripheral == nil,
              self.peripheralIdentity == nil,
              state == .scanning,
              case .scanning(_) = centralLifecycle else { return }
        transport.stopScan()
        state = .connecting
        // Bind this central manager to a fresh lifecycle before issuing the
        // connect. Every later central callback from this manager carries the
        // captured attempt through its proxy.
        generation &+= 1
        let attempt = generation
        centralLifecycle = .connecting(attempt)
        transport.delegateProxy.bind(to: attempt)
        transport.delegateProxy.bindPeripheralIdentity(peripheralIdentity)
        beginPeripheralAttempt(
            attempt,
            peripheral: peripheral,
            peripheralIdentity: peripheralIdentity
        )
        startTimeout(
            seconds: Self.connectionTimeout,
            generation: attempt,
            reason: L("remote_mic.error.connection_timeout"),
            isSatisfied: { [weak self] in
                guard let self else { return true }
                return self.generation != attempt || self.handshake.capabilitiesRequested
            }
        )
        transport.connect(to: peripheralIdentity)
    }

    fileprivate func routeCentralDidConnect(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        sourceAttempt: UInt64?
    ) {
        guard let attempt = currentCentralAttempt(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            sourceAttempt: sourceAttempt,
            allowConnected: false
        ) else { return }
        centralLifecycle = .connected(attempt)
        startTimeout(
            seconds: Self.initializationTimeout,
            generation: attempt,
            reason: L("remote_mic.error.initialization_timeout"),
            isSatisfied: { [weak self] in self?.handshake.isReady ?? false }
        )
        peripheral?.discoverServices([serviceUUID])
    }

    fileprivate func routeCentralDidFailToConnect(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        error: Error?,
        sourceAttempt: UInt64?
    ) {
        if currentCentralAttempt(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            sourceAttempt: sourceAttempt,
            allowConnected: false
        ) != nil {
            failAttempt(reason: L("remote_mic.error.connect_failed"))
            scheduleCentralRetirementCompletion(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                attempt: sourceAttempt
            )
            return
        }
        scheduleCentralRetirementCompletion(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            attempt: sourceAttempt
        )
    }

    fileprivate func routeCentralDidDisconnect(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        error: Error?,
        sourceAttempt: UInt64?
    ) {
        if currentCentralAttempt(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            sourceAttempt: sourceAttempt,
            allowConnected: true
        ) != nil {
            handleDisconnect()
            scheduleCentralRetirementCompletion(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                attempt: sourceAttempt
            )
            return
        }
        scheduleCentralRetirementCompletion(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            attempt: sourceAttempt
        )
    }

    /// Test-only source injection through the same route used by the central
    /// delegate proxy. The optional CoreBluetooth objects are intentionally
    /// absent; source attribution and lifecycle transitions are not fabricated
    /// by looking at a mutable peripheral state.
    func routeCentralCallbackForTesting(
        _ callback: XiaomiRemoteMicCentralTestCallback,
        attempt: UInt64,
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject
    ) {
        switch callback {
        case .didConnect:
            routeCentralDidConnect(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                peripheral: nil,
                sourceAttempt: attempt
            )
        case .didFailToConnect:
            routeCentralDidFailToConnect(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                peripheral: nil,
                error: nil,
                sourceAttempt: attempt
            )
        case .didDisconnect:
            routeCentralDidDisconnect(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                peripheral: nil,
                error: nil,
                sourceAttempt: attempt
            )
        }
    }

    /// Source gate for central callbacks. Unlike the previous object-state
    /// check, this requires the callback proxy's attempt and the lifecycle
    /// phase to agree. A direct bridge callback has no source envelope and is
    /// rejected for connection events.
    private func currentCentralAttempt(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        sourceAttempt: UInt64?,
        allowConnected: Bool
    ) -> UInt64? {
        guard let transport = centralTransport,
              transport.identity === managerIdentity,
              let activePeripheralIdentity = self.peripheralIdentity,
              activePeripheralIdentity === peripheralIdentity else { return nil }
        guard let sourceAttempt,
              activeConnectionAttempt == sourceAttempt,
              handshake.accepts(sourceAttempt) else { return nil }
        guard let active = centralLifecycle.attempt, active == sourceAttempt else { return nil }
        switch centralLifecycle {
        case .connecting:
            break
        case .connected:
            guard allowConnected else { return nil }
        default:
            return nil
        }
        return sourceAttempt
    }

    private func scheduleCentralRetirementCompletion(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        attempt: UInt64?
    ) {
        guard let attempt,
              let pending = pendingCentralRetirement,
              pending.attempt == attempt,
              pending.identity === managerIdentity,
              pending.peripheralKey.map({ $0 == ObjectIdentifier(peripheralIdentity) }) ?? true
        else { return }
        finishCentralRetirement(managerIdentity: managerIdentity, attempt: attempt)
    }
}

// MARK: - Source-bound peripheral callback routes

extension XiaomiRemoteMicBridge {
    fileprivate func routeDidDiscoverServices(
        _ peripheral: CBPeripheral,
        error: Error?,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(peripheral, attempt: attempt), error == nil else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            failAttempt(reason: L("remote_mic.error.service_missing"))
            return
        }
        peripheral.discoverCharacteristics(
            [CBUUID(string: RemoteMicProtocol.transmitUUID),
             CBUUID(string: RemoteMicProtocol.audioUUID),
             CBUUID(string: RemoteMicProtocol.controlUUID)],
            for: service
        )
    }

    fileprivate func routeDidDiscoverCharacteristics(
        _ peripheral: CBPeripheral,
        service: CBService,
        error: Error?,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(peripheral, attempt: attempt), error == nil else { return }
        let transmit = RemoteMicProtocol.transmitUUID.uppercased()
        let audio = RemoteMicProtocol.audioUUID.uppercased()
        let control = RemoteMicProtocol.controlUUID.uppercased()
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid.uuidString.uppercased() {
            case transmit:
                transmitCharacteristic = characteristic
                handshake.registerCharacteristic(.transmit)
            case audio:
                audioCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case control:
                controlCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        guard transmitCharacteristic != nil,
              audioCharacteristic != nil,
              controlCharacteristic != nil else {
            failAttempt(reason: L("remote_mic.error.characteristic_missing"))
            return
        }
        // Capabilities wait for didUpdateNotificationStateFor on both channels.
        requestCapabilitiesIfReady()
    }

    fileprivate func routeDidUpdateNotificationState(
        _ peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(peripheral, attempt: attempt), error == nil else { return }
        guard characteristic.isNotifying else { return }
        switch characteristic.uuid.uuidString.uppercased() {
        case RemoteMicProtocol.audioUUID.uppercased():
            handshake.confirmSubscription(.audio)
        case RemoteMicProtocol.controlUUID.uppercased():
            handshake.confirmSubscription(.control)
        default:
            return
        }
        requestCapabilitiesIfReady()
    }

    fileprivate func routeDidUpdateValue(
        _ peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?,
        attempt: UInt64
    ) {
        // A reused CBPeripheral object can deliver a late value from a previous
        // attempt; attribute it to the attempt that raised it and drop it when
        // this handshake no longer tracks that attempt.
        guard acceptsPeripheralCallback(peripheral, attempt: attempt), error == nil,
              let data = characteristic.value else { return }
        switch characteristic.uuid.uuidString.uppercased() {
        case RemoteMicProtocol.controlUUID.uppercased():
            handleControl(data, attempt: attempt)
        case RemoteMicProtocol.audioUUID.uppercased():
            handleAudio(data, attempt: attempt)
        default:
            break
        }
    }

    /// The common gate for every CBPeripheralDelegate callback. Unlike the old
    /// `attempt(for:)` lookup, the attempt here came from the delegate proxy
    /// that was installed for the connection lifecycle.
    private func acceptsPeripheralCallback(_ peripheral: CBPeripheral?, attempt: UInt64) -> Bool {
        guard activeConnectionAttempt == attempt,
              peripheralCallbackProxy?.attempt == attempt,
              handshake.accepts(attempt) else { return false }
        if let peripheral {
            guard peripheral === self.peripheral else { return false }
        }
        return true
    }

    /// Test-only event route used by `XiaomiRemoteMicPeripheralDelegateProxy`.
    /// It intentionally enters the same attempt gate and handlers as production
    /// delegate callbacks; it only omits unavailable CoreBluetooth value types.
    fileprivate func routeTestCallback(
        _ callback: XiaomiRemoteMicTestCallback,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(nil, attempt: attempt) else { return }
        switch callback {
        case .disconnect:
            handleDisconnect()
        case let .control(data):
            handleControl(data, attempt: attempt)
        case let .audio(data):
            handleAudio(data, attempt: attempt)
        }
    }
}
