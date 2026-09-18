import XCTest
@testable import OpenType

final class AudioSensitivityThresholdTests: XCTestCase {
    private func activity(
        _ thresholds: AudioActivityThresholds,
        rms: Float,
        frames: Int = 16_000
    ) -> AudioCaptureActivity {
        var activity = AudioCaptureActivity(thresholds: thresholds)
        activity.record(rms: rms, frameCount: frames)
        return activity
    }

    private func thresholds(
        gate: AudioSensitivity,
        weak: AudioSensitivity
    ) -> AudioActivityThresholds {
        AudioActivityThresholds(
            gate: gate.gateThresholds,
            weakSpeechEvidence: weak.weakSpeechEvidenceThresholds
        )
    }

    func testStandardSensitivityEqualsShippedDefaults() {
        XCTAssertEqual(
            AudioSensitivity.standard.gateThresholds,
            AudioActivityThresholds.default.gate
        )
        XCTAssertEqual(
            AudioSensitivity.standard.weakSpeechEvidenceThresholds,
            AudioActivityThresholds.default.weakSpeechEvidence
        )
        XCTAssertEqual(
            thresholds(gate: .standard, weak: .standard),
            AudioActivityThresholds.default
        )
    }

    func testGateSensitivityChangesGateBehavior() {
        let audibleForStandard: Float = 0.002
        XCTAssertTrue(
            activity(thresholds(gate: .standard, weak: .standard), rms: audibleForStandard)
                .hasMeaningfulAudio
        )
        XCTAssertFalse(
            activity(thresholds(gate: .conservative, weak: .standard), rms: audibleForStandard)
                .hasMeaningfulAudio
        )
        XCTAssertTrue(
            activity(thresholds(gate: .sensitive, weak: .standard), rms: audibleForStandard)
                .hasMeaningfulAudio
        )

        let quiet: Float = 0.001
        XCTAssertFalse(
            activity(thresholds(gate: .standard, weak: .standard), rms: quiet)
                .hasMeaningfulAudio
        )
        XCTAssertTrue(
            activity(thresholds(gate: .sensitive, weak: .standard), rms: quiet)
                .hasMeaningfulAudio
        )
    }

    func testWeakSpeechEvidenceIsIndependentOfGateSensitivity() {
        let rms: Float = 0.002
        let conservativeGate = activity(
            thresholds(gate: .conservative, weak: .standard),
            rms: rms
        )
        let sensitiveGate = activity(
            thresholds(gate: .sensitive, weak: .standard),
            rms: rms
        )

        XCTAssertNotEqual(conservativeGate.hasMeaningfulAudio, sensitiveGate.hasMeaningfulAudio)
        XCTAssertEqual(conservativeGate.hasWeakSpeechEvidence, sensitiveGate.hasWeakSpeechEvidence)
        XCTAssertTrue(conservativeGate.hasWeakSpeechEvidence)
    }

    func testWeakSpeechSensitivityChangesWeakJudgementOnly() {
        let rms: Float = 0.002
        let standard = activity(thresholds(gate: .standard, weak: .standard), rms: rms)
        let conservative = activity(thresholds(gate: .standard, weak: .conservative), rms: rms)
        let sensitive = activity(thresholds(gate: .standard, weak: .sensitive), rms: rms)

        XCTAssertTrue(standard.hasWeakSpeechEvidence)
        XCTAssertFalse(conservative.hasWeakSpeechEvidence)
        XCTAssertTrue(sensitive.hasWeakSpeechEvidence)

        XCTAssertTrue(standard.hasMeaningfulAudio)
        XCTAssertEqual(standard.hasMeaningfulAudio, conservative.hasMeaningfulAudio)
        XCTAssertEqual(standard.hasMeaningfulAudio, sensitive.hasMeaningfulAudio)
    }

    func testClampingBoundsAndNonFiniteFallback() {
        let clamped = AudioActivityThresholds(
            gate: .init(minimumAverageRMS: -1, minimumPeakRMS: 9),
            weakSpeechEvidence: .init(averageRMS: 0, peakRMS: .nan)
        ).clamped

        XCTAssertEqual(clamped.gate.minimumAverageRMS, AudioActivityThresholds.minimumAllowedRMS)
        XCTAssertEqual(clamped.gate.minimumPeakRMS, AudioActivityThresholds.maximumAllowedRMS)
        XCTAssertEqual(
            clamped.weakSpeechEvidence.averageRMS,
            AudioActivityThresholds.minimumAllowedRMS
        )
        XCTAssertEqual(
            clamped.weakSpeechEvidence.peakRMS,
            AudioActivityThresholds.default.weakSpeechEvidence.peakRMS
        )
    }

    func testSensitivitySettingsDefaultPersistAndRecoverFromInvalidValues() {
        let suiteName = "AudioSensitivityThresholdTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.audioGateSensitivity, .standard)
        XCTAssertEqual(settings.audioWeakSpeechSensitivity, .standard)
        XCTAssertEqual(settings.audioActivityThresholds, AudioActivityThresholds.default)

        settings.audioGateSensitivity = .sensitive
        settings.audioWeakSpeechSensitivity = .conservative

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.audioGateSensitivity, .sensitive)
        XCTAssertEqual(reloaded.audioWeakSpeechSensitivity, .conservative)
        XCTAssertEqual(
            reloaded.audioActivityThresholds,
            thresholds(gate: .sensitive, weak: .conservative)
        )

        defaults.set("bogus", forKey: "audioGateSensitivity")
        defaults.set("", forKey: "audioWeakSpeechSensitivity")

        let invalid = AppSettings(defaults: defaults)
        XCTAssertEqual(invalid.audioGateSensitivity, .standard)
        XCTAssertEqual(invalid.audioWeakSpeechSensitivity, .standard)
    }
}
