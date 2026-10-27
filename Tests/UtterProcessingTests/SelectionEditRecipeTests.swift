import Foundation
import XCTest
import UtterContracts
import UtterProcessing

final class SelectionEditRecipeTests: XCTestCase {
    func testPortableRecipeUsesTheFullSelectionAndNormalizesOneGeneration() async throws {
        let original = "  原文 e\u{301} 👩🏽‍💻\n" + String(repeating: "完整内容。", count: 200)
        var calls = 0
        let candidate = try await SelectionEditRecipe.candidate(selectedText: original,
            intent: .custom("Make a concise English reply"), inputLanguage: .auto,
            spokenCommand: "Make a concise English reply") { prompt, system, budget in
                calls += 1
                XCTAssertTrue(prompt.contains(original))
                XCTAssertTrue(prompt.contains("Make a concise English reply"))
                XCTAssertTrue(system.contains("final_text"))
                XCTAssertEqual(budget.maxTokens, 1280)
                XCTAssertEqual(budget.temperature, 0.15)
                return "<think>internal reasoning</think>{\"final_text\":\"Rewritten 👩🏽‍💻\"}"
            }
        XCTAssertEqual(candidate, "Rewritten 👩🏽‍💻")
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(original.hasPrefix("  原文 e\u{301} 👩🏽‍💻\n"))
    }

    func testEmptyInputsNeverInvokeTheExistingBackend() async {
        for (selection, instruction, expected) in [(" \n ", "rewrite", SelectionEditRecipe.Failure.emptySelection),
            ("original", " \n ", .emptyInstruction)] {
            do {
                _ = try await SelectionEditRecipe.candidate(selectedText: selection, intent: .custom(instruction),
                    inputLanguage: .english) { _, _, _ in XCTFail("Invalid input invoked generation"); return "candidate" }
                XCTFail("Invalid input produced a candidate")
            } catch { XCTAssertEqual(error as? SelectionEditRecipe.Failure, expected) }
        }
    }

    func testFailedOrReasoningOnlyGenerationNeverFallsBackToTheOriginal() async {
        do {
            _ = try await SelectionEditRecipe.candidate(selectedText: "original", intent: .concise,
                inputLanguage: .english) { _, _, _ in throw GenerationServiceError.modelUnavailable }
            XCTFail("Model failure invented a candidate")
        } catch { XCTAssertEqual(error as? GenerationServiceError, .modelUnavailable) }
        for output in [" \n ", "<think>still trying</think>", "<analysis>unfinished reasoning",
                       "{\"final_text\":\"\"}", "{\"action\":\"delete_selection\",\"confidence\":1}",
                       "{\"final_text\":\"\",\"text\":\"Deleted.\",\"reason\":\"delete_selection\"}",
                       "{\"action\":\"delete_selection\",\"text\":\"Deleted.\",\"confidence\":1}",
                       #"{"final_text":{"final_text":"","text":"Deleted.","reason":"delete_selection"}}"#,
                       #"{"final_text":{"action":"delete_selection","text":"Deleted.","confidence":1}}"#,
                       "```json\n{\"action\":\"delete_selection\",\"confidence\":1}\n```"] {
            do {
                _ = try await SelectionEditRecipe.candidate(selectedText: "original", intent: .concise,
                    inputLanguage: .english) { _, _, _ in output }
                XCTFail("Empty result fell back to original")
            } catch { XCTAssertEqual(error as? SelectionEditRecipe.Failure, .emptyCandidate) }
        }
    }

    func testCancelledGenerationCannotProduceAReviewableCandidate() async {
        let task = Task {
            try await SelectionEditRecipe.candidate(selectedText: "original", intent: .concise,
                inputLanguage: .english) { _, _, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "candidate"
                }
        }
        do { _ = try await task.value; XCTFail("Cancelled model result was accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testStrictSelectionHandlesNestedStringifiedAndFencedEnvelopes() {
        for output in [
            #"{"data":"{\"action\":\"delete_selection\",\"text\":\"Deleted.\",\"confidence\":1}"}"#,
            #"{"final_text":"{\"final_text\":\"\",\"text\":\"Deleted.\",\"reason\":\"delete_selection\"}"}"#,
            #"[{"text":"Deleted.","reason":"delete_selection"}]"#,
            "```json\n{\"final_text\":\"\",\"text\":\"Deleted.\",\"reason\":\"delete_selection\"}\n```",
        ] { XCTAssertEqual(SelectionEditRecipe.normalize(output), "") }
        for output in [#"{"response":{"rewritten_text":"Keep the notes. 👩🏽‍💻"}}"#,
            #"[{"type":"final_text","text":"Keep the notes. 👩🏽‍💻"}]"#,
            #"{"tool_calls":[{"function":{"arguments":"{\"final_text\":\"Keep the notes. 👩🏽‍💻\"}"}}]}"#,
            "```json\n{\"final_text\":\"Keep the notes. 👩🏽‍💻\"}\n```"] {
            XCTAssertEqual(SelectionEditRecipe.normalize(output), "Keep the notes. 👩🏽‍💻")
        }
    }

    func testStrictRecursiveObjectsRejectAmbiguousTextWhileOrdinaryParsingKeepsIt() {
        for output in [
            #"{"final_text":{"final_text":"","text":"Deleted.","reason":"delete_selection"}}"#,
            #"{"final_text":{"action":"delete_selection","text":"Deleted.","confidence":1}}"#,
            #"{"type":"final_text","value":{"action":"delete_selection","text":"Deleted.","confidence":1}}"#,
        ] {
            XCTAssertEqual(SelectionEditRecipe.normalize(output), "")
            XCTAssertEqual(LLMFinalTextOutput.text(from: output), "Deleted.")
        }
        for output in [#"{"final_text":{"value":"Keep the notes."}}"#,
            #"{"type":"final_text","content":{"value":"Keep the notes."}}"#,
            #"{"final_text":{"final_text":"Keep the notes.","text":"Deleted."}}"#] {
            XCTAssertEqual(SelectionEditRecipe.normalize(output), "Keep the notes.")
        }
        XCTAssertFalse(LLMFinalTextOutput.requiresExplicitFinalText)
    }
}
