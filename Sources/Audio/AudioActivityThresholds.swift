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

    /// Inclusive bounds every RMS threshold is clamped to before use, so a
    /// corrupted or out-of-range persisted value can never disable detection or
    /// force every recording to be treated as speech.
    static let minimumAllowedRMS: Float = 0.0001
    static let maximumAllowedRMS: Float = 0.05

    /// Returns a copy whose values lie within the allowed bounds. Non-finite
    /// values fall back to the corresponding default.
    var clamped: AudioActivityThresholds {
        AudioActivityThresholds(
            gate: Gate(
                minimumAverageRMS: Self.clamp(
                    gate.minimumAverageRMS,
                    fallback: Self.default.gate.minimumAverageRMS
                ),
                minimumPeakRMS: Self.clamp(
                    gate.minimumPeakRMS,
                    fallback: Self.default.gate.minimumPeakRMS
                )
            ),
            weakSpeechEvidence: WeakSpeechEvidence(
                averageRMS: Self.clamp(
                    weakSpeechEvidence.averageRMS,
                    fallback: Self.default.weakSpeechEvidence.averageRMS
                ),
                peakRMS: Self.clamp(
                    weakSpeechEvidence.peakRMS,
                    fallback: Self.default.weakSpeechEvidence.peakRMS
                )
            )
        )
    }

    private static func clamp(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, minimumAllowedRMS), maximumAllowedRMS)
    }
}
