import Foundation

/// Tracks whether a wireless-microphone session currently wants audio, and
/// whether the bridge may act on it.
///
/// The subtle rule this encodes: a caller that falls back to the system input
/// must leave no trace of wanting the remote. Otherwise a bridge that becomes
/// ready later would open the remote microphone in the middle of a system-input
/// session, and that session's stop would never close it again.
struct RemoteMicWantedState: Equatable {
    private(set) var isWanted = false
    private(set) var isStreaming = false

    /// True while the bridge should forward audio and may open the microphone.
    var isActive: Bool { isWanted || isStreaming }

    mutating func want() {
        isWanted = true
    }

    /// Releases the want. Returns whether a release actually happened, so the
    /// caller can fire "released" once.
    @discardableResult
    mutating func release() -> Bool {
        let had = isWanted
        isWanted = false
        return had
    }

    mutating func beginStreaming() {
        isStreaming = true
    }

    /// Drops both the want and the stream, returning whether a session was live
    /// so the caller can fire "stopped"/"released" once.
    @discardableResult
    mutating func reset() -> Bool {
        let wasLive = isActive
        isWanted = false
        isStreaming = false
        return wasLive
    }
}
