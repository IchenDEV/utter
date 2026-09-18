import Foundation

/// Numeric-only audio activity record used to calibrate the recording gate and
/// the weak-speech heuristic. It never carries audio samples or transcript
/// content.
struct AudioCaptureDiagnostic: Equatable, Sendable {
    let averageRMS: Float
    let maxRMS: Float
    let frameCount: Int
    let gateRejected: Bool

    init(activity: AudioCaptureActivity) {
        self.averageRMS = activity.averageRMS
        self.maxRMS = activity.maxRMS
        self.frameCount = activity.frameCount
        self.gateRejected = !activity.hasMeaningfulAudio
    }

    /// Stable, greppable single-line format for later corpus correlation.
    var logLine: String {
        String(
            format: "audio-activity averageRMS=%.6f maxRMS=%.6f frames=%d gateRejected=",
            Double(averageRMS),
            Double(maxRMS),
            frameCount
        ) + (gateRejected ? "true" : "false")
    }
}

enum AudioCaptureDiagnostics {
    static let environmentKey = "UTTER_AUDIO_DIAGNOSTICS"

    /// Disabled by default. Only debug builds opt in, via the environment
    /// variable, so release builds never log recording activity.
    static var isEnabled: Bool {
        #if DEBUG
        resolveEnabled(environment: ProcessInfo.processInfo.environment, isDebugBuild: true)
        #else
        false
        #endif
    }

    static func resolveEnabled(environment: [String: String], isDebugBuild: Bool) -> Bool {
        guard isDebugBuild else { return false }
        return environment[environmentKey] == "1"
    }

    static func log(_ activity: AudioCaptureActivity) {
        guard isEnabled else { return }
        Log.info("[AudioCapture] \(AudioCaptureDiagnostic(activity: activity).logLine)")
    }
}
