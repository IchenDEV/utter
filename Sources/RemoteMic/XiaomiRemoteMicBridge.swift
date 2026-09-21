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

    /// Monotonic attempt counter. Every callback checks that it still belongs to
    /// the current attempt, so a late callback from a failed attempt cannot
    /// advance the replacement's handshake.
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
        peripheral = nil
        transmitCharacteristic = nil
        audioCharacteristic = nil
        controlCharacteristic = nil
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

    fileprivate func handleControl(_ data: Data) {
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

    fileprivate func handleAudio(_ data: Data) {
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
            // Buffer while the pipeline is still starting so the opening word is
            // kept; forward directly once it is recording.
            if session.isRecording {
                onSamples?(samples)
            } else {
                preRoll.append(samples)
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
        guard isActive, self.peripheral == nil else { return }
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        state = .connecting
        let attempt = generation
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
        guard peripheral === self.peripheral else { return }
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral === self.peripheral else { return }
        failAttempt(reason: L("remote_mic.error.connect_failed"))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral === self.peripheral else { return }
        handleDisconnect()
    }
}

extension XiaomiRemoteMicBridge: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
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

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peripheral === self.peripheral else { return }
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

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === self.peripheral, error == nil else { return }
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

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // A reused CBPeripheral object can deliver a late value from a previous
        // attempt; ignore anything that is not the current peripheral.
        guard peripheral === self.peripheral else { return }
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid.uuidString.uppercased() {
        case RemoteMicProtocol.controlUUID.uppercased():
            handleControl(data)
        case RemoteMicProtocol.audioUUID.uppercased():
            handleAudio(data)
        default:
            break
        }
    }
}
