import Foundation

enum CaptureLivenessAction: Equatable {
    case healthy
    case wait
    case retry
    case fail
}

/// Decides whether a running capture is actually receiving audio.
///
/// A healthy input delivers a buffer about every 100 ms even when silent, so a
/// capture that has produced no frames after the grace period is stalled. It is
/// restarted once with a fresh format before the user is told.
enum CaptureLiveness {
    static let graceSeconds: TimeInterval = 1.5
    static let maxRetries = 1

    static func decide(elapsed: TimeInterval, framesReceived: Int, retriesUsed: Int) -> CaptureLivenessAction {
        if framesReceived > 0 { return .healthy }
        guard elapsed.isFinite, elapsed >= graceSeconds else { return .wait }
        return retriesUsed < maxRetries ? .retry : .fail
    }
}
