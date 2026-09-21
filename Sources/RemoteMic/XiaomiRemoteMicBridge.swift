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

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    /// Attempt of the currently active connection lifecycle. This is used only
    /// by central-manager lifecycle callbacks, which CoreBluetooth delivers
    /// without a source attempt. Peripheral data callbacks carry their attempt
    /// in `peripheralCallbackProxy` instead of reading this mutable value.
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

    /// Monotonic attempt counter. Peripheral callbacks carry their source
    /// attempt through the delegate proxy; central callbacks are checked at the
    /// current connection-state boundary because CoreBluetooth supplies no
    /// central source id.
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
        guard central == nil else {
            beginScan()
            return
        }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
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
        if let peripheral, peripheral.state == .connected {
            central?.cancelPeripheralConnection(peripheral)
        }
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
        resetPeripheral()
        handshake.reset()
        generation = 0
        state = .idle
    }

    /// Test-only: simulate a connect and return the attempt it bound.
    @discardableResult
    func simulateConnectForTesting() -> UInt64 {
        generation &+= 1
        let attempt = generation
        beginPeripheralAttempt(attempt)
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
        guard let central else { return }
        guard central.state == .poweredOn else { return }
        generation &+= 1
        resetPeripheral()
        resetStream()
        handshake.reset()
        capabilities = .default
        state = .scanning
        central.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func resetPeripheral() {
        peripheral?.delegate = nil
        peripheral = nil
        activeConnectionAttempt = nil
        peripheralCallbackProxy = nil
        transmitCharacteristic = nil
        audioCharacteristic = nil
        controlCharacteristic = nil
    }

    /// Starts a new peripheral lifecycle and installs the source-bound route.
    /// CoreBluetooth itself does not expose the attempt id on delegate events;
    /// this proxy is the lifecycle boundary that supplies it.
    private func beginPeripheralAttempt(_ attempt: UInt64, peripheral: CBPeripheral? = nil) {
        activeConnectionAttempt = attempt
        handshake.beginAttempt(attempt)
        let proxy = XiaomiRemoteMicPeripheralDelegateProxy(bridge: self, attempt: attempt)
        peripheralCallbackProxy = proxy
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
        if let peripheral, peripheral.state == .connected {
            central?.cancelPeripheralConnection(peripheral)
        }
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
            if let peripheral = self.peripheral, peripheral.state == .connected {
                return
            }
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
        switch central.state {
        case .poweredOn:
            beginScan()
        case .unauthorized:
            cancelTimeout()
            cancelReconnect()
            state = .unauthorized
        case .unsupported:
            cancelTimeout()
            cancelReconnect()
            state = .unsupported
        default:
            cancelTimeout()
            state = .idle
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isActive, self.peripheral == nil, state == .scanning else { return }
        central.stopScan()
        state = .connecting
        // Bind this connection to a fresh lifecycle proxy. A reused
        // CBPeripheral may still have an old proxy callback queued; that proxy
        // carries its old attempt and cannot pass the route gate below.
        generation &+= 1
        let attempt = generation
        beginPeripheralAttempt(attempt, peripheral: peripheral)
        startTimeout(
            seconds: Self.connectionTimeout,
            generation: attempt,
            reason: L("remote_mic.error.connection_timeout"),
            isSatisfied: { [weak self] in
                guard let self else { return true }
                return self.generation != attempt || self.handshake.capabilitiesRequested
            }
        )
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Central callbacks have no attempt token. CoreBluetooth serializes
        // them on the main delegate queue, so only accept a connected state for
        // the currently installed lifecycle. A late disconnect/failure after a
        // replacement has connected is rejected by the state checks below.
        guard let attempt = currentCentralAttempt(for: peripheral),
              peripheral.state == .connected else { return }
        startTimeout(
            seconds: Self.initializationTimeout,
            generation: attempt,
            reason: L("remote_mic.error.initialization_timeout"),
            isSatisfied: { [weak self] in self?.handshake.isReady ?? false }
        )
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        // A failed connection is terminal only while this lifecycle is
        // actually disconnected. This rejects an old failure delivered while a
        // reused object is already connecting/connected for its replacement.
        guard currentCentralAttempt(for: peripheral) != nil,
              peripheral.state == .disconnected else { return }
        failAttempt(reason: L("remote_mic.error.connect_failed"))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        // A disconnect raised for a superseded attempt must not tear down the
        // connection that replaced it. CoreBluetooth exposes no source id, so
        // the lifecycle boundary is the current object + disconnected state;
        // all data/handshake callbacks use the stronger proxy envelope below.
        guard currentCentralAttempt(for: peripheral) != nil,
              peripheral.state == .disconnected else { return }
        handleDisconnect()
    }

    /// Returns the current lifecycle for a central callback. Central delegate
    /// events do not carry a source attempt; state checks at their lifecycle
    /// boundary keep an old disconnect/failure from invalidating a replacement.
    private func currentCentralAttempt(for peripheral: CBPeripheral) -> UInt64? {
        guard peripheral === self.peripheral,
              let attempt = activeConnectionAttempt,
              handshake.accepts(attempt) else { return nil }
        return attempt
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
