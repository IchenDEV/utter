import AVFoundation
import Foundation
import XCTest
@testable import OpenType

@MainActor
final class IntegrationOutputTests: XCTestCase {
    func testImportedAudioRejectsNoSpeechBeforeTranscriptionOrFinalEvent() async throws {
        let store = registry()
        defer { store.cleanup() }
        store.registry.approve(IntegrationClient.localHTTP(tokenID: "token"))
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(mode: .direct), clientID: clientID)
        let coordinator = InputSessionCoordinator(service: service)
        let engine = TestSpeechEngine(transcript: "Vocabulary: Alpha, Beta, Gamma, Delta")
        coordinator.engineLoader = { _ in engine }
        coordinator.speechActivityOverrideForTesting = { _ in false }

        await assertThrowsIntegrationError(.noSpeechDetected) {
            _ = try await coordinator.processAudioFile(
                sessionID: session.id, clientID: clientID,
                audioURL: URL(fileURLWithPath: "/tmp/utter-missing-audio.wav"), cleanup: false
            )
        }
        XCTAssertEqual(engine.transcribeCount, 0)
        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .failed)
    }

    func testCoordinatorRejectsWeakAudioVocabularyEcho() {
        let store = registry()
        defer { store.cleanup() }
        let suite = "IntegrationVocabularyEcho-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.industryLexicon = .technology
        let coordinator = InputSessionCoordinator(
            service: makeService(registry: store.registry),
            settings: settings
        )
        coordinator.requestSettings = VoiceInputSettings(settings: settings)
        var activity = AudioCaptureActivity()
        activity.record(rms: 0.002, frameCount: 16_000)
        let echo = ["云原生", "容器编排", "微服务", "服务网格", "持续集成", "CI", "持续交付", "CD"]
            .joined(separator: ", ")

        XCTAssertThrowsError(try coordinator.prepareTranscript(echo, audioActivity: activity)) { error in
            XCTAssertEqual(error as? IntegrationError, .noSpeechDetected)
        }
    }

    func testAppDelegateSharesTextProcessorWithIntegrationCoordinator() {
        let delegate = AppDelegate()

        XCTAssertTrue(delegate.integrationSessionCoordinator.textProcessor === delegate.textProcessor)
    }

    func testServiceRejectsEmptyFinalText() async throws {
        let store = registry()
        defer { store.cleanup() }
        store.registry.approve(IntegrationClient.localHTTP(tokenID: "token"))
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(mode: .command), clientID: clientID)
        try await service.beginProcessing(sessionID: session.id, clientID: clientID)

        await assertThrowsIntegrationError(.operationFailed) {
            try await service.completeSession(sessionID: session.id, clientID: clientID, finalText: "   ")
        }
    }

    func testCoordinatorRejectsEmptyOutputBeforeCompleting() async {
        let store = registry()
        defer { store.cleanup() }
        store.registry.approve(IntegrationClient.localHTTP(tokenID: "token"))
        let service = makeService(registry: store.registry)
        let coordinator = InputSessionCoordinator(service: service)
        let active = InputSessionCoordinator.ActiveSession(
            sessionID: UUID(),
            clientID: clientID,
            engine: TestSpeechEngine(transcript: ""),
            languageCode: nil,
            mode: .direct,
            inputLanguage: .english,
            useScreenContext: false,
            streamingEnabled: false,
            screenContextTask: nil,
            client: IntegrationClient.localHTTP(tokenID: "token")
        )

        await assertThrowsIntegrationError(.operationFailed) {
            _ = try await coordinator.outputText(for: "   ", active: active)
        }
    }

    func testCoordinatorPreservesCombinedLocalModelFailureGuidance() async {
        let store = registry()
        defer { store.cleanup() }
        store.registry.approve(IntegrationClient.localHTTP(tokenID: "token"))
        let coordinator = InputSessionCoordinator(service: makeService(registry: store.registry))
        let active = InputSessionCoordinator.ActiveSession(
            sessionID: UUID(),
            clientID: clientID,
            engine: TestSpeechEngine(transcript: ""),
            languageCode: nil,
            mode: .direct,
            inputLanguage: .english,
            useScreenContext: false,
            streamingEnabled: false,
            screenContextTask: nil,
            client: IntegrationClient.localHTTP(tokenID: "token")
        )

        do {
            try await TextProcessor.withEspressoOutcomeTracking {
                await TextProcessor.recordEspressoOutcome(.unavailable)
                _ = try await coordinator.outputText(for: "   ", active: active)
            }
            XCTFail("Expected local model failure")
        } catch let error as IntegrationError {
            XCTAssertEqual(error, .operationFailedWithMessage(EspressoGenerationOutcome.unavailable.message))
            XCTAssertEqual(error.payload.error, "operation_failed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private extension IntegrationOutputTests {
    var clientID: String {
        IntegrationClient.localHTTP(tokenID: "token").id
    }

    func makeService(registry: IntegrationClientRegistry) -> OpenTypeService {
        OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token"),
            registry: registry
        )
    }

    func request(mode: OutputMode) -> InputSessionRequest {
        InputSessionRequest(mode: mode, language: .english, useScreenContext: false)
    }

    func registry() -> RegistryStore {
        let suiteName = "IntegrationOutputTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RegistryStore(
            registry: IntegrationClientRegistry(defaults: defaults),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    func assertThrowsIntegrationError(
        _ expected: IntegrationError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as IntegrationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }
}

private final class TestSpeechEngine: SpeechEngine, @unchecked Sendable {
    let transcript: String
    private(set) var transcribeCount = 0
    var isReady: Bool { true }

    init(transcript: String) {
        self.transcript = transcript
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        transcribeCount += 1
        return transcript
    }
}

private struct RegistryStore {
    let registry: IntegrationClientRegistry
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
