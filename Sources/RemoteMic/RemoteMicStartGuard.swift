import Foundation

/// Decides whether a remote voice-key start may commit once the pipeline has
/// finished its potentially slow preparation (engine/model load).
///
/// Kept pure so the rule is unit-testable and the pipeline's check is the same
/// one the tests exercise: a start whose key was released, or whose task was
/// cancelled, must not begin recording and must not fall back to the system
/// microphone.
enum RemoteMicStartGuard {
    /// - Parameters:
    ///   - remoteSessionToken: the latch the start was created for, or nil for a
    ///     local (hotkey) start that has no remote latch.
    ///   - isCancelled: whether the owning task was cancelled.
    ///   - isSessionCurrent: predicate asking the bridge whether the latch is
    ///     still live.
    static func shouldCommit(
        remoteSessionToken: UInt64?,
        isCancelled: Bool,
        isSessionCurrent: (UInt64) -> Bool
    ) -> Bool {
        guard let remoteSessionToken else { return true }
        guard !isCancelled else { return false }
        return isSessionCurrent(remoteSessionToken)
    }
}
