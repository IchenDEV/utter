import Foundation
import CoreBluetooth
import Combine
import UtterContracts

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
package final class XiaomiRemoteMicBridge: NSObject, ObservableObject {

    /// How long a connection, or the initialization sequence after it, may take
    /// before the attempt is failed and retried.
    package static let connectionTimeout: TimeInterval = 10
    package static let initializationTimeout: TimeInterval = 8

    @Published package internal(set) var state: RemoteMicBridgeState = .idle

    /// Decoded 16 kHz mono samples while a voice session is streaming.
    package var onSamples: (([Int16]) -> Void)?
    /// Fired when the remote stops streaming, including unexpected disconnects.
    package var onStreamStopped: (() -> Void)?
    /// Fired when the remote's voice key starts a voice session, with the latch
    /// token the caller must commit when its asynchronous start completes. The
    /// remote signals this on the ATVV control channel (`AUDIO_START` for the
    /// no-`START_SEARCH` interaction model), so the voice key drives Utter's
    /// recording without a separate HID key remap or an Input Monitoring
    /// permission.
    package var onVoiceKeyPressed: ((UInt64) -> Void)?
    /// Fired when the remote's voice key ends the session. The caller stops or
    /// cancels its in-flight start for the current latch.
    package var onVoiceKeyReleased: (() -> Void)?

    var centralTransport: XiaomiRemoteMicCentralTransport?
    var centralTransportFactory: (() -> XiaomiRemoteMicCentralTransport)?
    /// Retired transports stay alive until their terminal central callback (or
    /// a scan queue fence) completes. Keying by manager identity prevents a
    /// still-pending old context from being evicted by an arbitrary FIFO cap.
    var retiredCentralContexts: [ObjectIdentifier: XiaomiRemoteMicCentralTransport] = [:]
    var retiredPeripheralContexts: [ObjectIdentifier: XiaomiRemoteMicPeripheralContext] = [:]
    var pendingCentralRetirement: (
        identity: AnyObject,
        attempt: UInt64,
        peripheralKey: ObjectIdentifier?
    )?
    var centralLifecycle: XiaomiRemoteMicCentralLifecycle = .idle
    var scanRequestedWhileQuiescing = false
    var peripheral: CBPeripheral?
    var peripheralIdentity: AnyObject?
    /// Attempt of the currently active connection lifecycle. Callback routes
    /// compare their proxy-captured source against this value; no route
    /// derives an old callback's source by looking at the current peripheral.
    var activeConnectionAttempt: UInt64?
    /// Retained so CoreBluetooth can call the source-bound proxy. An old proxy
    /// may still deliver a queued callback, but its captured attempt will fail
    /// the bridge's current-lifecycle gate.
    var peripheralCallbackProxy: XiaomiRemoteMicPeripheralDelegateProxy?
    var transmitCharacteristic: CBCharacteristic?
    var audioCharacteristic: CBCharacteristic?
    var controlCharacteristic: CBCharacteristic?
    var handshake = RemoteMicHandshake()

    var capabilities = RemoteMicCapabilities.default
    var microphoneOpened = false
    /// ATVV v1.0 requires `MIC_CLOSE` to identify the stream announced by
    /// `AUDIO_START`; physical PTT/HTT sessions commonly use a non-zero id.
    var streamID: UInt8 = 0
    /// Latches the voice-key session synchronously, so a release or disconnect
    /// that arrives while the pipeline is still starting cancels the pending
    /// start instead of being ignored.
    var session = RemoteMicSession()
    /// Audio that arrives before the capture pipeline is ready, so the opening
    /// word is not clipped.
    var preRoll = RemoteMicPreRoll()
    var reconnectAttempts = 0
    var reconnectTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?
    var isActive = false
    var isClosed = false
    var ownedTasks: [UUID: Task<Void, Never>] = [:]
    var retirementWaiters: [CheckedContinuation<Void, Never>] = []

    /// Monotonic attempt counter. Both peripheral and central callbacks carry
    /// their source attempt through a lifecycle proxy. CoreBluetooth itself
    /// supplies no attempt id; the proxy is the app-owned source envelope.
    var generation: UInt64 = 0

    var accumulator = RemoteMicFrameAccumulator()
    var decoder = RemoteMicADPCMDecoder()
    var pendingSync: (predictor: Int, stepIndex: Int)?

    var serviceUUID: CBUUID { CBUUID(string: RemoteMicProtocol.serviceUUID) }

    let gainDB: () -> Double
    var streamGainDB: Double = 0

    package init(gainDB: @escaping () -> Double) {
        self.gainDB = gainDB
        super.init()
    }
}
