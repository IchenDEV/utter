import XCTest
@testable import OpenType

final class QwenRecognitionContextTests: XCTestCase {
    func testPromptIsBoundedAndDoesNotContainWholeLexicon() {
        let phrases = (1...30).map { "Term\($0)" }
        let prompt = QwenRecognitionPrompt(phrases: phrases)
        XCTAssertLessThanOrEqual(prompt.phrases.count, 8)
        XCTAssertLessThanOrEqual(prompt.text.count, 180)
        XCTAssertFalse(prompt.text.contains("Term30"))
        let deduplicated = QwenRecognitionPrompt(phrases: ["Alpha", "alpha", "Beta"])
        XCTAssertEqual(deduplicated.phrases, ["Alpha", "Beta"])
    }

    func testEchoRetriesOnceWithoutContextAndRejectsRepeatedEcho() async throws {
        let prompt = QwenRecognitionPrompt(phrases: ["Alpha", "Beta", "Gamma", "Delta"])
        var contexts: [String] = []
        let accepted = try await QwenContextRecovery.run(prompt: prompt) { context in
            contexts.append(context)
            return context.isEmpty ? "We shipped Alpha today." : "Vocabulary: Alpha, Beta, Gamma, Delta."
        } text: { $0 }
        XCTAssertEqual(accepted, "We shipped Alpha today.")
        XCTAssertEqual(contexts, [prompt.text, ""])

        contexts.removeAll()
        let rejected = try await QwenContextRecovery.run(prompt: prompt) { context in
            contexts.append(context)
            return "Alpha, Beta, Gamma, Delta"
        } text: { $0 }
        XCTAssertNil(rejected)
        XCTAssertEqual(contexts, [prompt.text, ""])
    }

    func testSingleSpokenTermIsNotClassedAsEcho() {
        let prompt = QwenRecognitionPrompt(phrases: ["Zyralith"])
        XCTAssertFalse(QwenPromptEcho.matches("We shipped Zyralith today.", prompt: prompt))
        XCTAssertFalse(QwenPromptEcho.matches("Zyralith", prompt: prompt))
        XCTAssertTrue(QwenPromptEcho.matches("Vocabulary: Zyralith.", prompt: prompt))
    }

    func testDetectsOrderedEchoAfterLeadingText() {
        let prompt = QwenRecognitionPrompt(phrases: ["Alpha", "Beta", "Gamma", "Delta"])
        XCTAssertTrue(QwenPromptEcho.matches(
            "Here are the terms, Alpha, Beta, Gamma, Delta", prompt: prompt
        ))
    }

    func testRetryFailureNeverReturnsPromptEcho() async {
        enum RetryFailure: Error { case failed }
        let prompt = QwenRecognitionPrompt(phrases: ["Alpha", "Beta", "Gamma", "Delta"])
        var attempts = 0
        do {
            _ = try await QwenContextRecovery.run(prompt: prompt) { _ -> String in
                attempts += 1
                if attempts == 2 { throw RetryFailure.failed }
                return "Alpha, Beta, Gamma, Delta"
            } text: { $0 }
            XCTFail("A failed retry must not return the first transcript")
        } catch RetryFailure.failed {
            XCTAssertEqual(attempts, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
