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

/// CoreBluetooth central that connects a Xiaomi Bluetooth Remote 2 Pro over the
/// ATVV profile and turns its audio notifications into PCM frames.
///
/// The remote keeps its own microphone stream private to the ATVV channel; this
/// bridge decodes that stream in-process, so Utter needs neither the vendor's
/// virtual audio driver nor a second application.
final class XiaomiRemoteMicBridge: NSObject, ObservableObject {
    static let shared = XiaomiRemoteMicBridge()

    @Published private(set) var state: RemoteMicBridgeState = .idle

    /// Decoded 16 kHz mono samples while a voice session is streaming.
    var onSamples: (([Int16]) -> Void)?
    /// Fired when the remote stops streaming, including unexpected disconnects.
    var onStreamStopped: (() -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var transmitCharacteristic: CBCharacteristic?
    private var audioCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?

    private var capabilities = RemoteMicCapabilities.default
    private var capabilitiesConfirmed = false
    private var microphoneOpened = false
    private var streaming = false
    private var captureWanted = false
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var isActive = false

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
        captureWanted = false
        reconnectTask?.cancel()
        reconnectTask = nil
        closeMicrophoneIfNeeded()
        resetStream()
        if let peripheral, peripheral.state == .connected {
            central?.cancelPeripheralConnection(peripheral)
        }
        resetPeripheral()
        state = .idle
    }

    /// Marks the session as wanted and asks the remote to open its microphone.
    /// Audio is only forwarded while a session is wanted.
    @discardableResult
    func beginCapture() -> Bool {
        captureWanted = true
        if !isActive { activate() }
        guard peripheral?.state == .connected, capabilitiesConfirmed else { return false }
        openMicrophoneIfNeeded()
        return true
    }

    func endCapture() {
        guard captureWanted else { return }
        captureWanted = false
        closeMicrophoneIfNeeded()
        if !streaming {
            resetStream()
            onStreamStopped?()
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
        streaming = false
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
    }

    private func startStreaming() {
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
        guard !streaming else { return }
        streaming = true
    }

    private func stopStreaming() {
        guard streaming else { return }
        resetStream()
        onStreamStopped?()
    }

    // MARK: - Scanning

    private func beginScan() {
        guard let central else { return }
        guard central.state == .poweredOn else { return }
        resetPeripheral()
        resetStream()
        capabilitiesConfirmed = false
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

    private func scheduleReconnect() {
        guard isActive else { return }
        reconnectTask?.cancel()
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
        if streaming || captureWanted {
            resetStream()
            onStreamStopped?()
        }
        capabilitiesConfirmed = false
        microphoneOpened = false
        resetPeripheral()
        if isActive { scheduleReconnect() }
    }

    fileprivate func handleControl(_ data: Data) {
        let bytes = Array(data)
        guard let opcode = bytes.first.flatMap(RemoteMicControlOpcode.init(rawValue:)) else { return }

        switch opcode {
        case .capabilities:
            guard let parsed = RemoteMicCapabilities.parse(data) else {
                state = .failed(reason: L("remote_mic.error.invalid_response"))
                return
            }
            capabilities = parsed
            guard RemoteMicProtocol.supportsAudio(sampleRate: parsed.sampleRate) else {
                state = .failed(reason: L("remote_mic.error.unsupported_codec"))
                closeMicrophoneIfNeeded()
                return
            }
            capabilitiesConfirmed = true
            reconnectAttempts = 0
            state = .ready(deviceName: peripheral?.name ?? "MI RC")
            if captureWanted { openMicrophoneIfNeeded() }
        case .microphoneOpenRequest:
            openMicrophoneIfNeeded()
        case .streamStart:
            guard captureWanted else { return }
            if bytes.count >= 3 {
                let codec = bytes[2]
                capabilities.selectedCodec = codec
                capabilities.sampleRate = codec == 0x02 ? 16_000 : 8_000
            }
            guard RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate) else {
                state = .failed(reason: L("remote_mic.error.unsupported_codec"))
                return
            }
            startStreaming()
        case .streamStop:
            resetStream()
            if captureWanted { openMicrophoneIfNeeded() }
        case .sync:
            guard bytes.count >= 7 else { return }
            let bits = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
            pendingSync = (Int(Int16(bitPattern: bits)), Int(bytes[6]))
            accumulator.reset()
        }
    }

    fileprivate func handleAudio(_ data: Data) {
        guard captureWanted, capabilitiesConfirmed else { return }
        if !streaming { startStreaming() }
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
            onSamples?(samples)
        }
    }
}

extension XiaomiRemoteMicBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScan()
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unsupported
        default:
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
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        peripheral.discoverServices([serviceUUID])
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
            state = .failed(reason: L("remote_mic.error.service_missing"))
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
            state = .failed(reason: L("remote_mic.error.characteristic_missing"))
            return
        }
        _ = write(RemoteMicProtocol.getCapabilities)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
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
