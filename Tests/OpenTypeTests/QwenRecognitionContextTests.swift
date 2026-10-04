import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterMLX
import UtterRuntime
import XCTest
@testable import UtterPresentation

final class QwenRecognitionContextTests: XCTestCase {
    @MainActor
    func testMountedQwenProviderSelectsTheSharedIndustryVocabulary() async throws {
        let suite = "QwenVocabulary-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.lexicons(),
            DataPlugins.diagnostics(QwenContextDiagnostics()), ModelPlugins.artifacts(), ModelPlugins.files(),
            ModelPlugins.resourceAccess(), ModelPlugins.speechProviders(), MLXPlugins.qwenSpeech()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        let descriptor = try XCTUnwrap(runtime.service(SpeechServices.providers).descriptors.first { $0.id == "speech.qwen" })
        XCTAssertEqual(descriptor.recognitionVocabulary, .all)
        let dictionary = PersonalDictionarySnapshot(entries: [], editRules: [],
            industryLexicon: try runtime.service(DataServices.lexicons).snapshot(for: .technology))
        XCTAssertTrue(dictionary.recognitionPhrases.contains("Kubernetes"))
        XCTAssertTrue(dictionary.recognitionPhrases.contains("Redis"))
        let prompt = QwenRecognitionPrompt(phrases: dictionary.recognitionPhrases)
        XCTAssertFalse(prompt.phrases.isEmpty)
        XCTAssertLessThanOrEqual(prompt.phrases.count, 8)
        XCTAssertLessThanOrEqual(prompt.text.count, 180)
        try await runtime.stop()
    }
    func testCancellationAfterEchoPreventsContextFreeRetry() async throws {
        let prompt = QwenRecognitionPrompt(phrases: ["Alpha", "Beta", "Gamma", "Delta"])
        let task = Task {
            try await QwenContextRecovery.run(prompt: prompt) { context in
                withUnsafeCurrentTask { $0?.cancel() }
                return "Vocabulary: Alpha, Beta, Gamma, Delta."
            } text: { $0 }
        }
        do { _ = try await task.value; XCTFail("Cancelled recognition should stop") }
        catch is CancellationError { }
    }

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

private struct QwenContextDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
