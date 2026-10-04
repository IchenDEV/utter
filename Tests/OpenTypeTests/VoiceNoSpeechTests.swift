import XCTest
import UtterContracts
import UtterMediaContracts
import UtterSession

@MainActor
final class VoiceNoSpeechTests: XCTestCase {
    func testSpeechEvidenceRejectsAudioBeforeASRAndDelivery() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.evidence.hasSpeech = false
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local)
        try driver.start(intent)
        try await driver.waitForRecording(intent.id)
        await driver.stop(intent.id)
        XCTAssertEqual(driver.snapshot.phase, .failed)
        XCTAssertEqual(driver.snapshot.error, L("status.no_speech_detected"))
        XCTAssertTrue(fixture.engine.transcribed.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
        try await fixture.runtime.stop()
    }

    func testWeakAudioVocabularyEchoNeverReachesAnyRecipeOrOutput() async throws {
        for mode in [TextProcessingMode.direct, .formatting, .command, .translation(.english)] {
            for instant in [false, true] {
                let fixture = try VoiceWorkflowFixture()
                defer { fixture.remove() }
                fixture.defaults.set("technology", forKey: "industryLexicon")
                fixture.defaults.set(instant, forKey: "enableInstantInsert")
                fixture.capture.recording.rms = 0.002
                try await fixture.start()
                let lexicons = try fixture.runtime.service(DataServices.lexicons)
                let phrases = Array(lexicons.snapshot(for: .technology).recognitionPhrases.prefix(8))
                XCTAssertEqual(phrases.count, 8)
                fixture.engine.transcript = phrases.joined(separator: ", ")
                let driver = try fixture.runtime.service(SessionServices.execution)
                let intent = SessionIntent(input: .local, mode: mode)
                try driver.start(intent)
                try await driver.waitForRecording(intent.id)
                await driver.stop(intent.id)
                XCTAssertEqual(driver.snapshot.phase, .failed, "\(mode), instant: \(instant)")
                XCTAssertTrue(fixture.output.requests.isEmpty)
                XCTAssertTrue(fixture.recipe.requests.isEmpty)
                XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
                try await fixture.runtime.stop()
            }
        }
    }
}
