import XCTest
@testable import OpenType

final class TranscriptionSanitizerTests: XCTestCase {
    func testCollapsesRepeatedTranscriptMoreThanTwice() {
        XCTAssertEqual(
            TranscriptionSanitizer.prepare(
                "Write a short release note. Write a short release note. Write a short release note."
            ),
            "Write a short release note."
        )
        XCTAssertEqual(
            TranscriptionSanitizer.prepare("帮我整理一下这段话 帮我整理一下这段话 帮我整理一下这段话"),
            "帮我整理一下这段话"
        )
    }

    func testKeepsShortRepeatedUtterances() {
        XCTAssertEqual(TranscriptionSanitizer.prepare("yes yes yes"), "yes yes yes")
        XCTAssertEqual(TranscriptionSanitizer.prepare("OK OK OK"), "OK OK OK")
    }

    func testDropsExplicitNoSpeechArtifactsButKeepsLiteralShortWords() {
        XCTAssertNil(TranscriptionSanitizer.prepare("(无)"))
        XCTAssertNil(TranscriptionSanitizer.prepare("[BLANK_AUDIO]"))
        XCTAssertNil(TranscriptionSanitizer.prepare("<|nospeech|>"))

        XCTAssertEqual(TranscriptionSanitizer.prepare("无"), "无")
        XCTAssertEqual(TranscriptionSanitizer.prepare("silence"), "silence")
    }

    func testDropsWeakAudioHallucinatedTemplateTails() {
        var weakAudio = AudioCaptureActivity()
        weakAudio.record(rms: 0.002, frameCount: 16_000)

        XCTAssertEqual(
            TranscriptionSanitizer.prepare(
                "Thank you for watching.",
                audioActivity: weakAudio
            ),
            "Thank you for watching."
        )
        XCTAssertEqual(
            TranscriptionSanitizer.prepare(
                "今天下午同步一下。谢谢观看。",
                audioActivity: weakAudio
            ),
            "今天下午同步一下。"
        )
        XCTAssertEqual(
            TranscriptionSanitizer.prepare(
                "Ship the release notes today. Subtitles by Amara.org",
                audioActivity: weakAudio
            ),
            "Ship the release notes today."
        )
    }

    func testKeepsHallucinationLikeWordsWhenAudioIsStrong() {
        var strongAudio = AudioCaptureActivity()
        strongAudio.record(rms: 0.02, frameCount: 16_000)

        XCTAssertEqual(
            TranscriptionSanitizer.prepare(
                "Thank you for watching.",
                audioActivity: strongAudio
            ),
            "Thank you for watching."
        )
    }
}
