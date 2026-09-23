import AppKit
import XCTest
@testable import OpenType

private final class VocabularyEchoEngine: SpeechEngine, @unchecked Sendable {
    let transcript: String
    var isReady: Bool { true }

    init(transcript: String) { self.transcript = transcript }

    func transcribe(audioURL: URL?, language: String?) async throws -> String { transcript }
}

@MainActor
final class VoicePipelineSilentInsertionTests: XCTestCase {
    func testNonSpeechGateStopsHallucinatedShortWordBeforeASR() async {
        let suite = "VoicePipelineNoSpeech-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let state = AppState()
        let pipeline = VoicePipeline(appState: state)
        let engine = VocabularyEchoEngine(transcript: "嗯。")
        pipeline.engineOverride = engine
        pipeline.speechActivityOverrideForTesting = { _ in false }
        var insertionCount = 0
        pipeline.textInserter.insertOverrideForTesting = { _ in
            insertionCount += 1
            return .success
        }
        var activity = AudioCaptureActivity()
        activity.record(rms: 0.002, frameCount: 16_000)

        await pipeline.processRecording(
            audioURL: nil,
            audioActivity: activity,
            language: nil,
            settings: VoiceInputSettings(settings: settings),
            inputMode: .dictation,
            targetApp: nil
        )

        XCTAssertEqual(insertionCount, 0)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.rawTranscription.isEmpty)
    }

    func testVocabularyEchoNeverReachesInsertionAcrossOutputModes() async {
        let suite = "VoicePipelineSilentInsertionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.industryLexicon = .technology
        let terms = ["云原生", "容器编排", "微服务", "服务网格", "持续集成", "CI", "持续交付", "CD"]
        let transcript = terms.joined(separator: ", ")
        var activity = AudioCaptureActivity()
        activity.record(rms: 0.002, frameCount: 16_000)
        XCTAssertTrue(activity.hasMeaningfulAudio)

        let cases: [(OutputMode, VoiceInputMode, Bool)] = [
            (.direct, .dictation, false),
            (.processed, .dictation, false),
            (.processed, .dictation, true),
            (.command, .dictation, false),
            (.direct, .translation(.english), false),
        ]
        for (outputMode, inputMode, instantInsert) in cases {
            settings.outputMode = outputMode
            settings.enableInstantInsert = instantInsert
            let state = AppState()
            let pipeline = VoicePipeline(appState: state)
            pipeline.engineOverride = VocabularyEchoEngine(transcript: transcript)
            pipeline.speechActivityOverrideForTesting = { _ in true }
            var insertionCount = 0
            pipeline.textInserter.insertOverrideForTesting = { _ in
                insertionCount += 1
                return .success
            }

            await pipeline.processRecording(
                audioURL: nil,
                audioActivity: activity,
                language: nil,
                settings: VoiceInputSettings(settings: settings),
                inputMode: inputMode,
                targetApp: nil
            )

            XCTAssertEqual(insertionCount, 0, "mode: \(outputMode), instant: \(instantInsert)")
            XCTAssertEqual(state.phase, .idle)
            XCTAssertTrue(state.lastInsertedText.isEmpty)
        }
    }
}
