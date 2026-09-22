import Foundation

/// A capture surface the release decision can act on. `AudioCaptureManager` is
/// final, so the decision is expressed against this seam and the production
/// release path applies exactly the same rule to the real manager.
@MainActor
protocol RemoteMicReleaseTarget: AnyObject {
    var hasActiveRecording: Bool { get }
    var isRunning: Bool { get }
    func cancelSession()
}

extension RemoteMicCaptureManager: RemoteMicReleaseTarget {}

/// What a remote voice-key release must do, given the capture state.
///
/// A committed recording must be *stopped* so the pipeline can read its WAV for
/// transcription; cancelling it would nil the file. A start that never committed
/// must be *cancelled* so nothing is recorded.
@MainActor
struct RemoteMicReleaseDecision: Equatable {
    let shouldStopPipeline: Bool
    let shouldCancelCapture: Bool

    static func decide(hasActiveRecording: Bool, sessionIsLive: Bool) -> RemoteMicReleaseDecision {
        guard sessionIsLive || hasActiveRecording else {
            return RemoteMicReleaseDecision(shouldStopPipeline: false, shouldCancelCapture: false)
        }
        return RemoteMicReleaseDecision(
            shouldStopPipeline: hasActiveRecording,
            shouldCancelCapture: !hasActiveRecording
        )
    }

    /// Applies the release to a real target and returns what the caller must do
    /// to the pipeline. This is the production entry point, so a counterexample
    /// exercises the same wiring the app uses.
    @discardableResult
    static func applyRelease(
        to target: RemoteMicReleaseTarget,
        stopPipeline: () -> Void
    ) -> RemoteMicReleaseDecision {
        let decision = decide(
            hasActiveRecording: target.hasActiveRecording,
            sessionIsLive: target.isRunning
        )
        if decision.shouldCancelCapture {
            target.cancelSession()
        }
        if decision.shouldStopPipeline {
            stopPipeline()
        }
        return decision
    }
}

/// What disabling the feature must do. The bridge's release callback is
/// suppressed once the setting is off, so shutdown must stop the pipeline
/// itself instead of relying on that callback.
struct RemoteMicShutdownDecision: Equatable {
    let shouldStopPipeline: Bool

    static func decide(hasActiveRecording: Bool) -> RemoteMicShutdownDecision {
        RemoteMicShutdownDecision(shouldStopPipeline: hasActiveRecording)
    }
}
