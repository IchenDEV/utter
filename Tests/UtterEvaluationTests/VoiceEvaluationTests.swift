import Foundation
import XCTest
@testable import UtterEvaluation

final class VoiceEvaluationTests: XCTestCase {
    private let arguments = ["--corpus", "/tmp/corpus.jsonl", "--model", "/tmp/model",
                             "--model-id", "fixture", "--output", "/tmp/results.jsonl"]

    func testCorpusIsRejectedBeforeInferenceWhenIDsOrBudgetAreInvalid() throws {
        let record = #"{"id":"time","language":"zh","faithful_reference":"三点","repetitions":5}"#
        XCTAssertEqual(try VoiceEvaluationCase.load(Data(record.utf8), maximumRuns: 5).count, 1)
        XCTAssertThrowsError(try VoiceEvaluationCase.load(Data(record.utf8), maximumRuns: 4))
        XCTAssertThrowsError(try VoiceEvaluationCase.load(Data((record + "\n" + record).utf8), maximumRuns: 10))
        XCTAssertThrowsError(try VoiceEvaluationCase.load(Data(), maximumRuns: 10))
    }

    func testUnknownModesAndMissingTranslationTargetCannotUseFormattingDefaults() {
        for record in [
            #"{"id":"x","language":"zh","faithful_reference":"你好","mode":"unknown"}"#,
            #"{"id":"x","language":"zh","faithful_reference":"你好","mode":"translation"}"#,
            #"{"id":"x","language":"zh","faithful_reference":"你好","repetitions":0}"#,
        ] {
            XCTAssertThrowsError(try VoiceEvaluationCase.load(Data(record.utf8), maximumRuns: 100))
        }
    }

    func testExplicitModelAndFiniteBudgetsAreRequired() throws {
        let parsed = try VoiceEvaluationArguments(arguments)
        XCTAssertEqual(parsed.maximumRuns, 100)
        XCTAssertEqual(parsed.caseTimeout, 120)
        XCTAssertEqual(parsed.maxTokens, 4_096)
        XCTAssertThrowsError(try VoiceEvaluationArguments(arguments + ["--max-tokens", "5000"]))
        XCTAssertThrowsError(try VoiceEvaluationArguments(arguments + ["--max-runs", "0"]))
        XCTAssertThrowsError(try VoiceEvaluationArguments(arguments + ["--remote", "https://example.test"]))
        XCTAssertThrowsError(try VoiceEvaluationArguments(arguments + ["--model", "/other"]))
        XCTAssertThrowsError(try VoiceEvaluationArguments(Array(arguments.dropLast(2))))
    }

    func testOutputCannotOverwriteCorpusOrModel() {
        for destination in ["/tmp/corpus.jsonl", "/tmp/model", "/tmp/model/config.json"] {
            XCTAssertThrowsError(try VoiceEvaluationArguments(Array(arguments.dropLast(2)) + ["--output", destination]))
        }
    }

    func testSpeechEvaluationRequiresAnExplicitLocalProviderAndCompleteSelection() throws {
        XCTAssertThrowsError(try VoiceEvaluationArguments(arguments + ["--speech-provider", "whisper"]))
        let selection = try VoiceEvaluationArguments(arguments + ["--speech-provider", "whisper",
            "--speech-model", "/tmp/whisper", "--speech-model-id", "base"])
        XCTAssertEqual(selection.speech?.providerID, "speech.whisper")
        XCTAssertEqual(selection.speech?.modelID, "base")
        XCTAssertThrowsError(try VoiceEvaluationArguments(arguments + ["--speech-provider", "apple",
            "--speech-model", "/tmp/whisper", "--speech-model-id", "base"]))
        XCTAssertThrowsError(try VoiceEvaluationArguments(Array(arguments.dropLast(2)) + ["--output", "/tmp/whisper/tokenizer.json",
            "--speech-provider", "whisper", "--speech-model", "/tmp/whisper", "--speech-model-id", "base"]))
    }

    func testInvalidLexiconTargetAndExpectationFailDuringCorpusPreflight() {
        for field in [#""lexicon":"unknown""#, #""target_language":"unknown""#,
                      #""expected_outcome":"unknown""#, #""audio_file":" ""#] {
            let record = "{\"id\":\"x\",\"language\":\"zh\",\"faithful_reference\":\"你好\",\(field)}"
            XCTAssertThrowsError(try VoiceEvaluationCase.load(Data(record.utf8), maximumRuns: 100))
        }
    }

    func testTokenBudgetIncludesEveryGenerationAndFactCheck() async throws {
        let budget = EvaluationTokenBudget(limit: 4_096)
        let generation = try await budget.reserve(3_328)
        let checker = try await budget.reserve(768)
        XCTAssertEqual(generation + checker, 4_096)
        do { _ = try await budget.reserve(1); XCTFail("The fact check cannot bypass the total token budget") }
        catch VoiceEvaluationError.tokenBudgetExceeded {}
        let reserved = await budget.reserved
        XCTAssertEqual(reserved, 4_096)
    }
}
