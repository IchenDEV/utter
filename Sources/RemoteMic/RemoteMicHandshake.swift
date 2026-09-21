import Foundation

/// Pure gate for the ATVV handshake: which subscriptions are confirmed, whether
/// the capability request may be sent, and whether the connection is usable.
///
/// Kept free of CoreBluetooth so the ordering rules are unit-testable: the host
/// must not request capabilities before **both** the audio and control
/// notifications are confirmed, and readiness requires a parsed 16 kHz
/// capability response.
struct RemoteMicHandshake: Equatable {
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

    /// True exactly when the capability request should be written: all
    /// characteristics known, both notifications confirmed, and not yet sent.
    var shouldRequestCapabilities: Bool {
        hasAllCharacteristics && subscriptionsReady && !capabilitiesRequested
    }

    /// Reserves the request so it is only written once per attempt.
    mutating func markCapabilitiesRequested() {
        capabilitiesRequested = true
    }

    /// Records the capability response, rejecting a non-16 kHz codec.
    @discardableResult
    mutating func confirmCapabilities(_ capabilities: RemoteMicCapabilities) -> Bool {
        guard RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate) else {
            return false
        }
        capabilitiesConfirmed = true
        return true
    }

    var isReady: Bool { capabilitiesConfirmed }

    mutating func reset() {
        self = RemoteMicHandshake()
    }

    enum CharacteristicKind {
        case transmit
        case audio
        case control
    }
}
