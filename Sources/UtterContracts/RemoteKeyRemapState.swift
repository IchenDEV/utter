import Foundation

/// Whether the remote's voice-key (F5) remap is in effect. State only: no key
/// events are observed to produce it.
package enum RemoteKeyRemapState: Equatable, Sendable {
    /// The user turned the setting off, or the app is shutting down.
    case off
    /// Enabled, but no matching remote has a HID service.
    case noRemote
    /// A remote is expected (it just reconnected or became ready) but its HID service is not visible yet.
    case waitingForService
    /// The mapping is written and read back.
    case active
    /// Another tool keeps overwriting the F5 mapping; Utter stopped touching it.
    case conflict
    /// The mapping could not be written or verified after bounded retries.
    case failed
}
