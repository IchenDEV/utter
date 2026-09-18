import Foundation

/// Tunable audio-activity thresholds, split into two independent groups so the
/// recording gate and the weak-speech heuristic can be calibrated separately.
///
/// `gate` drives `AudioCaptureActivity.hasMeaningfulAudio` (whether a recording
/// is handed to ASR at all); `weakSpeechEvidence` drives
/// `AudioCaptureActivity.hasWeakSpeechEvidence` (whether `TranscriptionSanitizer`
/// may collapse repetition or strip hallucinated tails). Loosening one group
/// must never move the other's decision.
struct AudioActivityThresholds: Equatable, Sendable {
    struct Gate: Equatable, Sendable {
        var minimumAverageRMS: Float
        var minimumPeakRMS: Float
    }

    struct WeakSpeechEvidence: Equatable, Sendable {
        var averageRMS: Float
        var peakRMS: Float
    }

    var gate: Gate
    var weakSpeechEvidence: WeakSpeechEvidence

    /// Production values, identical to the constants they replaced.
    static let `default` = AudioActivityThresholds(
        gate: Gate(minimumAverageRMS: 0.0015, minimumPeakRMS: 0.005),
        weakSpeechEvidence: WeakSpeechEvidence(averageRMS: 0.004, peakRMS: 0.012)
    )
}
