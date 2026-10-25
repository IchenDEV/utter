import Foundation

/// What the remote button mapping is doing, as the settings page reports it. State only.
package enum RemoteButtonMappingState: Equatable, Sendable {
    /// The user turned it off, or the voice-key remap it depends on is off. Nothing is touched.
    case off
    /// Input Monitoring is not granted, so Utter cannot see presses and silences nothing.
    /// `canAsk`: the system has not been asked yet, so a prompt can still appear.
    case needsPermission(canAsk: Bool)
    /// The permission was reported as granted but the system still refuses to open the source.
    case needsRestart
    /// Allowed, but the remote is not connected or its key service is not visible yet.
    case waitingForRemote
    /// Presses are observed and the owned keys are silenced.
    case active
    /// Another tool keeps overwriting one of the keys Utter owns; Utter stopped touching them.
    case conflict
    /// The press source or the key mapping could not be set up after bounded retries.
    case failed
}
