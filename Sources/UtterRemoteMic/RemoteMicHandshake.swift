import Foundation

/// Pure gate for the ATVV handshake: which subscriptions are confirmed, whether
/// the capability request may be sent, and whether the connection is usable.
///
/// Kept free of CoreBluetooth so the ordering rules are unit-testable: the host
/// must not request capabilities before **both** the audio and control
/// notifications are confirmed, and readiness requires a parsed 16 kHz
/// capability response.
package struct RemoteMicHandshake: Equatable {
    package init(attempt: UInt64 = 0) { self.attempt = attempt }
    /// Identity of the connection attempt this handshake belongs to. CoreBluetooth
    /// may deliver a queued callback for a previous attempt on the same
    /// `CBPeripheral` object after a reconnect; stamping each callback with the
    /// attempt it belongs to is the only way to reject it once the new attempt
    /// has already requested capabilities.
    package private(set) var attempt: UInt64 = 0
    package private(set) var hasTransmit = false
    package private(set) var subscriptions: Set<RemoteMicSubscription> = []
    package private(set) var capabilitiesRequested = false
    package private(set) var capabilitiesConfirmed = false

    package var hasAllCharacteristics: Bool {
        hasTransmit && subscriptionsReady
    }

    package var subscriptionsReady: Bool {
        subscriptions.contains(.audio) && subscriptions.contains(.control)
    }

    /// True when every characteristic has been discovered.
    package mutating func registerCharacteristic(_ kind: CharacteristicKind) {
        switch kind {
        case .transmit: hasTransmit = true
        case .audio: break
        case .control: break
        }
    }

    /// Records a confirmed notification subscription.
    package mutating func confirmSubscription(_ subscription: RemoteMicSubscription) {
        subscriptions.insert(subscription)
    }

    /// Starts a new attempt. Every callback carries the attempt it was raised
    /// for; a mismatch means the callback belongs to a superseded connection.
    package mutating func beginAttempt(_ attempt: UInt64) {
        self = RemoteMicHandshake(attempt: attempt)
    }

    /// True when `attempt` is the connection this handshake is tracking.
    package func accepts(_ attempt: UInt64) -> Bool {
        attempt == self.attempt
    }

    /// True exactly when the capability request should be written: all
    /// characteristics known, both notifications confirmed, and not yet sent.
    package var shouldRequestCapabilities: Bool {
        hasAllCharacteristics && subscriptionsReady && !capabilitiesRequested
    }

    /// Reserves the request so it is only written once per attempt.
    package mutating func markCapabilitiesRequested() {
        capabilitiesRequested = true
    }

    /// Records the capability response.
    ///
    /// Rejects a response that arrives before this attempt asked for one, and a
    /// non-16 kHz codec. The request gate matters: a late capability frame from a
    /// previous attempt on a reused peripheral must not mark the new attempt
    /// ready.
    @discardableResult
    package mutating func confirmCapabilities(_ capabilities: RemoteMicCapabilities) -> Bool {
        guard capabilitiesRequested else { return false }
        guard RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate) else {
            return false
        }
        capabilitiesConfirmed = true
        return true
    }

    package var isReady: Bool { capabilitiesConfirmed }

    package mutating func reset() {
        self = RemoteMicHandshake(attempt: attempt)
    }

    package enum CharacteristicKind {
        case transmit
        case audio
        case control
    }
}
