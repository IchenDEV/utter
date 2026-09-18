import XCTest
@testable import OpenType

final class AudioCaptureActivityTests: XCTestCase {
    private let sampleRMS: Float = 0.002
    private let sampleFrames = 16_000

    private func activity(
        gate: AudioActivityThresholds.Gate,
        weak: AudioActivityThresholds.WeakSpeechEvidence,
        rms: Float
    ) -> AudioCaptureActivity {
        var activity = AudioCaptureActivity(
            thresholds: AudioActivityThresholds(gate: gate, weakSpeechEvidence: weak)
        )
        activity.record(rms: rms, frameCount: sampleFrames)
        return activity
    }

    func testDefaultThresholdsMatchPreviousConstants() {
        XCTAssertEqual(AudioActivityThresholds.default.gate.minimumAverageRMS, 0.0015)
        XCTAssertEqual(AudioActivityThresholds.default.gate.minimumPeakRMS, 0.005)
        XCTAssertEqual(AudioActivityThresholds.default.weakSpeechEvidence.averageRMS, 0.004)
        XCTAssertEqual(AudioActivityThresholds.default.weakSpeechEvidence.peakRMS, 0.012)
    }

    func testGateAndWeakSpeechEvidenceUseIndependentThresholdGroups() {
        let defaultWeak = AudioActivityThresholds.default.weakSpeechEvidence

        let strictGate = activity(
            gate: .init(minimumAverageRMS: 0.5, minimumPeakRMS: 0.5),
            weak: defaultWeak,
            rms: sampleRMS
        )
        XCTAssertFalse(strictGate.hasMeaningfulAudio)
        XCTAssertTrue(strictGate.hasWeakSpeechEvidence)

        let looseGate = activity(
            gate: .init(minimumAverageRMS: 0.001, minimumPeakRMS: 0.001),
            weak: defaultWeak,
            rms: sampleRMS
        )
        XCTAssertTrue(looseGate.hasMeaningfulAudio)
        XCTAssertTrue(looseGate.hasWeakSpeechEvidence)

        let strictWeak = activity(
            gate: .init(minimumAverageRMS: 0.001, minimumPeakRMS: 0.001),
            weak: .init(averageRMS: 0.0001, peakRMS: 0.0001),
            rms: sampleRMS
        )
        XCTAssertTrue(strictWeak.hasMeaningfulAudio)
        XCTAssertFalse(strictWeak.hasWeakSpeechEvidence)
    }

    func testDiagnosticRecordFormatIsStable() {
        var activity = AudioCaptureActivity()
        activity.record(rms: 0.002, frameCount: 16_000)

        let diagnostic = AudioCaptureDiagnostic(activity: activity)
        XCTAssertEqual(diagnostic.averageRMS, 0.002, accuracy: 1e-6)
        XCTAssertEqual(diagnostic.maxRMS, 0.002, accuracy: 1e-6)
        XCTAssertEqual(diagnostic.frameCount, 16_000)
        XCTAssertFalse(diagnostic.gateRejected)
        XCTAssertEqual(
            diagnostic.logLine,
            "audio-activity averageRMS=0.002000 maxRMS=0.002000 frames=16000 gateRejected=false"
        )
    }

    func testDiagnosticFlagsGateRejection() {
        var activity = AudioCaptureActivity()
        activity.record(rms: 0.0001, frameCount: 16_000)

        let diagnostic = AudioCaptureDiagnostic(activity: activity)
        XCTAssertTrue(diagnostic.gateRejected)
        XCTAssertEqual(
            diagnostic.logLine,
            "audio-activity averageRMS=0.000100 maxRMS=0.000100 frames=16000 gateRejected=true"
        )
    }

    func testDiagnosticResolutionRequiresDebugBuildAndOptIn() {
        XCTAssertFalse(
            AudioCaptureDiagnostics.resolveEnabled(environment: [:], isDebugBuild: true)
        )
        XCTAssertFalse(
            AudioCaptureDiagnostics.resolveEnabled(
                environment: ["UTTER_AUDIO_DIAGNOSTICS": "0"],
                isDebugBuild: true
            )
        )
        XCTAssertTrue(
            AudioCaptureDiagnostics.resolveEnabled(
                environment: ["UTTER_AUDIO_DIAGNOSTICS": "1"],
                isDebugBuild: true
            )
        )
        XCTAssertFalse(
            AudioCaptureDiagnostics.resolveEnabled(
                environment: ["UTTER_AUDIO_DIAGNOSTICS": "1"],
                isDebugBuild: false
            )
        )
    }
}
