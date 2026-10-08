import Foundation

/// The remote voice-key session lifecycle: press → start → release → stop.
///
/// The pipeline that starts recording is asynchronous (it may wait for a model
/// to load), so a `STREAM_STOP` or a disconnect can arrive before recording is
/// actually live. This type latches the intent synchronously and gives the
/// caller a token, so:
///
/// - a start may only commit once;
/// - a release that arrives before the start commits cancels the pending start
///   instead of being ignored; and
/// - a late start completion for a cancelled generation cannot begin recording.
package struct RemoteMicSession: Equatable {
    package init() {}
    package enum Phase: Equatable {
        case idle
        case starting
        case recording
    }

    package private(set) var phase: Phase = .idle
    /// Increments on every press so completions from an older press are stale.
    package private(set) var generation: UInt64 = 0

    /// A press: starts a new generation and enters `starting`.
    /// Returns the token the async start must present when it completes.
    package mutating func press() -> UInt64 {
        generation &+= 1
        phase = .starting
        return generation
    }

    /// Commits a pending start. Returns false when the token is stale or the
    /// session has moved on, so the caller must not begin recording.
    package mutating func commitStart(token: UInt64) -> Bool {
        guard phase == .starting, token == generation else { return false }
        phase = .recording
        return true
    }

    /// A release. Returns whether this generation was still live, i.e. whether
    /// the caller must stop or cancel the in-flight recording.
    package mutating func release() -> Bool {
        switch phase {
        case .idle:
            return false
        case .starting, .recording:
            phase = .idle
            generation &+= 1
            return true
        }
    }

    /// A disconnect or feature shutdown behaves like a release.
    package mutating func invalidate() -> Bool {
        release()
    }

    /// True while the caller must still act on this generation.
    package var isLive: Bool { phase != .idle }
    package var isStarting: Bool { phase == .starting }
    package var isRecording: Bool { phase == .recording }
}
