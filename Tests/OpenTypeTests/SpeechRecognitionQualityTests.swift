import XCTest
@testable import OpenType

final class SpeechRecognitionQualityTests: XCTestCase {
    func testWhisperModelSelectionResolvesQualityAliasInsteadOfDeviceFallback() {
        let available = [
            "openai_whisper-base",
            "openai_whisper-large-v3",
            "openai_whisper-large-v3-v20240930_626MB",
            "openai_whisper-large-v3-turbo_954MB",
        ]

        XCTAssertEqual(
            WhisperModelSelection.resolve(
                requested: "large-v3",
                available: available,
                fallback: "openai_whisper-large-v3-v20240930_626MB"
            ),
            "openai_whisper-large-v3-v20240930_626MB"
        )
    }

    func testWhisperModelSelectionPreservesExplicitFullModelID() {
        let requested = "openai_whisper-large-v3-turbo_954MB"

        XCTAssertEqual(
            WhisperModelSelection.resolve(
                requested: requested,
                available: ["openai_whisper-base", requested],
                fallback: "openai_whisper-base"
            ),
            requested
        )
    }

    func testWhisperModelSelectionMigratesStaleBuildWithinFamily() {
        XCTAssertEqual(
            WhisperModelSelection.resolve(
                requested: "openai_whisper-large-v3-v20240930_547MB",
                available: [
                    "openai_whisper-base",
                    "openai_whisper-large-v3-v20250701_626MB",
                ],
                fallback: "openai_whisper-base"
            ),
            "openai_whisper-large-v3-v20250701_626MB"
        )
    }

    func testWhisperVariantDoesNotMistakeTurboForLargeV3() {
        XCTAssertFalse(
            WhisperModelSelection.matches(
                "openai_whisper-large-v3-turbo_954MB",
                variant: "large-v3"
            )
        )
        XCTAssertFalse(
            WhisperModelSelection.matches(
                "openai_whisper-large-v3-v20240930_turbo_632MB",
                variant: "large-v3"
            )
        )
        XCTAssertTrue(
            WhisperModelSelection.matches(
                "openai_whisper-large-v3-v20240930_turbo_632MB",
                variant: "large-v3-turbo"
            )
        )
    }

    func testRecognitionContextUsesEnabledCanonicalTermsAndDeduplicates() {
        let context = SpeechRecognitionContext(dictionaryEntries: [
            DictionaryEntry(original: "open type", replacement: "OpenType", enabled: true),
            DictionaryEntry(original: "whisper kit", replacement: "WhisperKit", enabled: true),
            DictionaryEntry(original: "duplicate", replacement: "opentype", enabled: true),
            DictionaryEntry(original: "disabled", replacement: "Disabled", enabled: false),
            DictionaryEntry(original: "blank", replacement: " ", enabled: true),
        ])

        XCTAssertEqual(context.phrases, ["OpenType", "WhisperKit"])
        XCTAssertEqual(
            context.whisperPrompt(language: "zh"),
            "以下是普通话听写。专有名词：OpenType, WhisperKit。"
        )
    }

    func testRecognitionContextCapsAppleContextualPhraseLimit() {
        let context = SpeechRecognitionContext(
            phrases: (0..<120).map { "term-\($0)" }
        )

        XCTAssertEqual(context.phrases.count, 100)
    }

    func testWhisperPromptBudgetKeepsWholeEarlyAndLaterTerms() {
        let context = SpeechRecognitionContext(
            phrases: ["OpenType", String(repeating: "x", count: 80), "MLX"]
        )

        let prompt = context.whisperPromptTokens(
            language: nil,
            maximumCount: 34,
            tokenize: { Array($0.utf8).map(Int.init) }
        ).map { String(decoding: $0.map(UInt8.init), as: UTF8.self) }

        XCTAssertEqual(prompt, "Dictation terms: OpenType, MLX.")
    }

    func testAppleCompatibleDictationPresetChangesAfterOneMinute() {
        XCTAssertEqual(
            AppleSpeechAnalyzer.dictationPreset(forDuration: 30),
            .shortDictation
        )
        XCTAssertEqual(
            AppleSpeechAnalyzer.dictationPreset(forDuration: 60),
            .shortDictation
        )
        XCTAssertEqual(
            AppleSpeechAnalyzer.dictationPreset(forDuration: 60.001),
            .longDictation
        )
    }
}
