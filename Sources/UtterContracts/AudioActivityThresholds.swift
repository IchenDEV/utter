import Foundation

/// Tunable audio-activity thresholds, split into two independent groups so the
/// recording gate and the weak-speech heuristic can be calibrated separately.
///
/// `gate` drives `AudioCaptureActivity.hasMeaningfulAudio` (whether a recording
/// is handed to ASR at all); `weakSpeechEvidence` drives
/// `AudioCaptureActivity.hasWeakSpeechEvidence` (whether `TranscriptionSanitizer`
/// may collapse repetition or strip hallucinated tails). Loosening one group
/// must never move the other's decision.
package struct AudioActivityThresholds: Equatable, Sendable {
    package struct Gate: Equatable, Sendable {
        package var minimumAverageRMS: Float
        package var minimumPeakRMS: Float

        package init(minimumAverageRMS: Float, minimumPeakRMS: Float) {
            self.minimumAverageRMS = minimumAverageRMS
            self.minimumPeakRMS = minimumPeakRMS
        }
    }

    package struct WeakSpeechEvidence: Equatable, Sendable {
        package var averageRMS: Float
        package var peakRMS: Float

        package init(averageRMS: Float, peakRMS: Float) {
            self.averageRMS = averageRMS
            self.peakRMS = peakRMS
        }
    }

    package var gate: Gate
    package var weakSpeechEvidence: WeakSpeechEvidence

    /// Production values, identical to the constants they replaced.
    package static let `default` = AudioActivityThresholds(
        gate: Gate(minimumAverageRMS: 0.0015, minimumPeakRMS: 0.005),
        weakSpeechEvidence: WeakSpeechEvidence(averageRMS: 0.004, peakRMS: 0.012)
    )

    /// Inclusive bounds every RMS threshold is clamped to before use, so a
    /// corrupted or out-of-range persisted value can never disable detection or
    /// force every recording to be treated as speech.
    package static let minimumAllowedRMS: Float = 0.0001
    package static let maximumAllowedRMS: Float = 0.05

    /// Returns a copy whose values lie within the allowed bounds. Non-finite
    /// values fall back to the corresponding default.
    package var clamped: AudioActivityThresholds {
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

    package init(gate: Gate, weakSpeechEvidence: WeakSpeechEvidence) {
        self.gate = gate
        self.weakSpeechEvidence = weakSpeechEvidence
    }
}
