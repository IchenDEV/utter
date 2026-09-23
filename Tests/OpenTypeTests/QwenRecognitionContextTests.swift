import XCTest
@testable import OpenType

final class QwenRecognitionContextTests: XCTestCase {
    func testPromptIsBoundedAndDoesNotContainWholeLexicon() {
        let phrases = (1...30).map { "Term\($0)" }
        let prompt = QwenRecognitionPrompt(phrases: phrases)
        XCTAssertLessThanOrEqual(prompt.phrases.count, 8)
        XCTAssertLessThanOrEqual(prompt.text.count, 180)
        XCTAssertFalse(prompt.text.contains("Term30"))
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
}
