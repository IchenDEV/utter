import Foundation

/// Pure gate for the ATVV handshake: which subscriptions are confirmed, whether
/// the capability request may be sent, and whether the connection is usable.
///
/// Kept free of CoreBluetooth so the ordering rules are unit-testable: the host
/// must not request capabilities before **both** the audio and control
/// notifications are confirmed, and readiness requires a parsed 16 kHz
/// capability response.
struct RemoteMicHandshake: Equatable {
    /// Identity of the connection attempt this handshake belongs to. CoreBluetooth
    /// may deliver a queued callback for a previous attempt on the same
    /// `CBPeripheral` object after a reconnect; stamping each callback with the
    /// attempt it belongs to is the only way to reject it once the new attempt
    /// has already requested capabilities.
    private(set) var attempt: UInt64 = 0
    private(set) var hasTransmit = false
    private(set) var subscriptions: Set<RemoteMicSubscription> = []
    private(set) var capabilitiesRequested = false
    private(set) var capabilitiesConfirmed = false

    var hasAllCharacteristics: Bool {
        hasTransmit && subscriptionsReady
    }

    var subscriptionsReady: Bool {
        subscriptions.contains(.audio) && subscriptions.contains(.control)
    }

    /// True when every characteristic has been discovered.
    mutating func registerCharacteristic(_ kind: CharacteristicKind) {
        switch kind {
        case .transmit: hasTransmit = true
        case .audio: break
        case .control: break
        }
    }

    /// Records a confirmed notification subscription.
    mutating func confirmSubscription(_ subscription: RemoteMicSubscription) {
        subscriptions.insert(subscription)
    }

    /// Starts a new attempt. Every callback carries the attempt it was raised
    /// for; a mismatch means the callback belongs to a superseded connection.
    mutating func beginAttempt(_ attempt: UInt64) {
        self = RemoteMicHandshake(attempt: attempt)
    }

    /// True when `attempt` is the connection this handshake is tracking.
    func accepts(_ attempt: UInt64) -> Bool {
        attempt == self.attempt
    }

    /// True exactly when the capability request should be written: all
    /// characteristics known, both notifications confirmed, and not yet sent.
    var shouldRequestCapabilities: Bool {
        hasAllCharacteristics && subscriptionsReady && !capabilitiesRequested
    }

    /// Reserves the request so it is only written once per attempt.
    mutating func markCapabilitiesRequested() {
        capabilitiesRequested = true
    }

    /// Records the capability response.
    ///
    /// Rejects a response that arrives before this attempt asked for one, and a
    /// non-16 kHz codec. The request gate matters: a late capability frame from a
    /// previous attempt on a reused peripheral must not mark the new attempt
    /// ready.
    @discardableResult
    mutating func confirmCapabilities(_ capabilities: RemoteMicCapabilities) -> Bool {
        guard capabilitiesRequested else { return false }
        guard RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate) else {
            return false
        }
        capabilitiesConfirmed = true
        return true
    }

    var isReady: Bool { capabilitiesConfirmed }

    mutating func reset() {
        self = RemoteMicHandshake(attempt: attempt)
    }

    enum CharacteristicKind {
        case transmit
        case audio
        case control
    }
}
