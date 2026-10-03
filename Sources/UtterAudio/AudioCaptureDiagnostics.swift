import UtterContracts
import Foundation

/// Numeric-only audio activity record used to calibrate the recording gate and
/// the weak-speech heuristic. It never carries audio samples or transcript
/// content.
package struct AudioCaptureDiagnostic: Equatable, Sendable {
    package let averageRMS: Float
    package let maxRMS: Float
    package let frameCount: Int
    package let gateRejected: Bool

    package init(activity: AudioCaptureActivity) {
        self.averageRMS = activity.averageRMS
        self.maxRMS = activity.maxRMS
        self.frameCount = activity.frameCount
        self.gateRejected = !activity.hasMeaningfulAudio
    }

    /// Stable, greppable single-line format for later corpus correlation.
    package var logLine: String {
        String(
            format: "audio-activity averageRMS=%.6f maxRMS=%.6f frames=%d gateRejected=",
            Double(averageRMS),
            Double(maxRMS),
            frameCount
        ) + (gateRejected ? "true" : "false")
    }
}

package enum AudioCaptureDiagnostics {
    package static let environmentKey = "UTTER_AUDIO_DIAGNOSTICS"

    /// Disabled by default. Only debug builds opt in, via the environment
    /// variable, so release builds never log recording activity.
    package static var isEnabled: Bool {
        #if DEBUG
        resolveEnabled(environment: ProcessInfo.processInfo.environment, isDebugBuild: true)
        #else
        false
        #endif
    }

    package static func resolveEnabled(environment: [String: String], isDebugBuild: Bool) -> Bool {
        guard isDebugBuild else { return false }
        return environment[environmentKey] == "1"
    }

    package static func log(_ activity: AudioCaptureActivity, diagnostics: Log) {
        guard isEnabled else { return }
        diagnostics.info("[AudioCapture] \(AudioCaptureDiagnostic(activity: activity).logLine)")
    }
}
