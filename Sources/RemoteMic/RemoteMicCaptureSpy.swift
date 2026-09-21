import AVFoundation
import Foundation

/// Test-only observation point for the pipeline's remote-capture path.
///
/// `AudioCaptureManager` is final, so a counterexample that must prove "capture
/// was never reached" injects this instead of subclassing it. Production never
/// sets it.
@MainActor
protocol RemoteMicCaptureSpy: AnyObject {
    /// The latch the pipeline would use, or nil when no session is live.
    var currentToken: UInt64? { get }
    /// Records a capture start; returns whether it succeeded.
    func start(token: UInt64) -> Bool
}
