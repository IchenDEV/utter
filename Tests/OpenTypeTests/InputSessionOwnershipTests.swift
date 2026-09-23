import Foundation
import XCTest
@testable import OpenType

@MainActor
final class InputSessionOwnershipTests: XCTestCase {
    func testCancelledLeaseRemainsBusyUntilWorkDrains() throws {
        let ownership = InputSessionOwnership()
        let old = try ownership.acquire()
        ownership.cancel(old)
        XCTAssertThrowsError(try ownership.check(old))
        XCTAssertThrowsError(try ownership.acquire())
        ownership.release(old)
        let next = try ownership.acquire()
        ownership.release(old)
        XCTAssertTrue(ownership.isBusy)
        XCTAssertNoThrow(try ownership.check(next))
    }

    func testFilePreparationBlocksMenuBarAndCancellationCannotStartCapture() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        let barrier = SessionBarrier()
        fixture.coordinator.engineLoader = { _ in
            await barrier.wait()
            return SessionEngine()
        }
        let session = try await fixture.create()
        let operation = Task {
            try await fixture.coordinator.processAudioFile(
                sessionID: session.id, clientID: fixture.clientID,
                audioURL: URL(fileURLWithPath: "/unused.wav"), cleanup: false
            )
        }
        await barrier.entered()
        XCTAssertTrue(fixture.ownership.isBusy)
        XCTAssertTrue(fixture.coordinator.isBusy)
        let pipeline = VoicePipeline(appState: AppState(), ownership: fixture.ownership)
        let capture = CaptureSpySource()
        capture.currentToken = 1
        pipeline.remoteCaptureSpy = capture
        pipeline.engineOverride = SessionEngine()
        await pipeline.start()
        XCTAssertEqual(capture.startInvocations, 0)
        try await fixture.coordinator.cancel(sessionID: session.id, clientID: fixture.clientID)
        XCTAssertTrue(fixture.ownership.isBusy, "cancel must not reuse a still-running loader")
        await barrier.open()
        do { _ = try await operation.value; XCTFail("cancelled work completed") } catch { }
        XCTAssertFalse(fixture.ownership.isBusy)
        XCTAssertEqual(try fixture.service.session(session.id, clientID: fixture.clientID)?.state, .cancelled)
    }

    func testCancelledTranscriptionCannotPublishOrReleaseNextSession() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        let barrier = SessionBarrier()
        let engine = SessionEngine()
        engine.transcription = { await barrier.wait(); return "late old transcript" }
        fixture.coordinator.engineLoader = { _ in engine }
        let old = try await fixture.create()
        let operation = Task {
            try await fixture.coordinator.processAudioFile(
                sessionID: old.id, clientID: fixture.clientID,
                audioURL: URL(fileURLWithPath: "/unused.wav"), cleanup: false
            )
        }
        await barrier.entered()
        try await fixture.coordinator.cancel(sessionID: old.id, clientID: fixture.clientID)
        let next = try await fixture.create()
        do {
            _ = try await fixture.coordinator.processAudioFile(
                sessionID: next.id, clientID: fixture.clientID,
                audioURL: URL(fileURLWithPath: "/unused.wav"), cleanup: false
            )
            XCTFail("old work is still using the engine")
        } catch { XCTAssertEqual(error as? IntegrationError, .busy) }
        await barrier.open()
        do { _ = try await operation.value; XCTFail("cancelled work completed") } catch { }
        let events = try fixture.service.snapshotEvents(sessionID: old.id, clientID: fixture.clientID)
        XCTAssertFalse(events.contains { $0.type == .textFinal || $0.type == .transcriptFinal })
        XCTAssertEqual(try fixture.service.session(next.id, clientID: fixture.clientID)?.state, .created)
        XCTAssertFalse(fixture.ownership.isBusy)
    }

    func testDisconnectOfAnotherClientDoesNotCancelOwner() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        let barrier = SessionBarrier()
        fixture.coordinator.engineLoader = { _ in await barrier.wait(); return SessionEngine() }
        let session = try await fixture.create()
        let operation = Task {
            try await fixture.coordinator.startRecording(sessionID: session.id, clientID: fixture.clientID)
        }
        await barrier.entered()
        fixture.coordinator.releaseActiveSessionForShutdown(clientID: "unrelated-client")
        XCTAssertTrue(fixture.coordinator.isBusy)
        XCTAssertEqual(try fixture.service.session(session.id, clientID: fixture.clientID)?.state, .created)
        try await fixture.coordinator.cancel(sessionID: session.id, clientID: fixture.clientID)
        await barrier.open()
        do { try await operation.value; XCTFail("cancelled start completed") } catch { }
        XCTAssertFalse(fixture.ownership.isBusy)
    }
    func testMenuBarReleaseDuringPreparationPreventsLateStart() async {
        let ownership = InputSessionOwnership()
        let pipeline = VoicePipeline(appState: AppState(), ownership: ownership)
        let barrier = SessionBarrier()
        let capture = CaptureSpySource()
        capture.currentToken = 1
        pipeline.engineOverride = SessionEngine()
        pipeline.remoteCaptureSpy = capture
        pipeline.engineLoadBarrier = { await barrier.wait() }
        let start = Task { await pipeline.start() }
        await barrier.entered()
        await pipeline.stop()
        XCTAssertTrue(ownership.isBusy)
        await barrier.open()
        await start.value
        XCTAssertFalse(ownership.isBusy)
        XCTAssertEqual(capture.startInvocations, 0)
    }

    func testSettingsAndEngineSelectionAreFrozenAtAdmission() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        fixture.settings.enableStreamingRecognitionBeta = false
        fixture.settings.inputLanguage = .english
        fixture.settings.speechEngine = .apple
        let session = try await fixture.create()
        _ = try fixture.coordinator.reserve(sessionID: session.id, clientID: fixture.clientID)
        let snapshot = try XCTUnwrap(fixture.coordinator.requestSettings)
        fixture.settings.enableStreamingRecognitionBeta = true
        fixture.settings.inputLanguage = .chinese
        fixture.settings.speechEngine = .volc
        fixture.settings.outputMode = .command
        let effective = fixture.coordinator.effectiveSettings(for: InputSessionRequest())
        XCTAssertFalse(effective.streamingEnabled)
        XCTAssertEqual(effective.mode, .direct)
        XCTAssertEqual(snapshot.inputLanguage, .english)
        XCTAssertEqual(snapshot.speech.type, .apple)
        try await fixture.coordinator.cancel(sessionID: session.id, clientID: fixture.clientID)
    }

    func testTerminalCommitWritesHistoryExactlyOnce() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        let session = try await fixture.create()
        try await fixture.service.beginProcessing(sessionID: session.id, clientID: fixture.clientID)
        var records = 0
        try fixture.service.commitSession(sessionID: session.id, clientID: fixture.clientID, finalText: "done") {
            records += 1
        }
        XCTAssertThrowsError(try fixture.service.commitSession(
            sessionID: session.id, clientID: fixture.clientID, finalText: "duplicate", record: { records += 1 }
        ))
        XCTAssertEqual(records, 1)
        let events = try fixture.service.snapshotEvents(sessionID: session.id, clientID: fixture.clientID)
        XCTAssertEqual(events.filter { $0.type == .textFinal }.count, 1)
    }

    func testCancelledSessionCannotCommitPreparedHistory() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        let session = try await fixture.create()
        _ = try fixture.coordinator.reserve(sessionID: session.id, clientID: fixture.clientID)
        try await fixture.service.beginProcessing(sessionID: session.id, clientID: fixture.clientID)
        var records = 0
        fixture.coordinator.pendingHistory = { records += 1 }
        try await fixture.coordinator.cancel(sessionID: session.id, clientID: fixture.clientID)
        XCTAssertThrowsError(try fixture.coordinator.commitOutput("late", sessionID: session.id, clientID: fixture.clientID))
        XCTAssertEqual(records, 0)
    }

    func testUnauthorizedCancelCannotReleaseResources() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        let session = try await fixture.create()
        _ = try fixture.coordinator.reserve(sessionID: session.id, clientID: fixture.clientID)
        do {
            try await fixture.coordinator.cancel(sessionID: session.id, clientID: "unregistered")
            XCTFail("unauthorized cancellation succeeded")
        } catch { }
        XCTAssertTrue(fixture.ownership.isBusy)
        try await fixture.coordinator.cancel(sessionID: session.id, clientID: fixture.clientID)
        XCTAssertFalse(fixture.ownership.isBusy)
    }

    func testMissingEngineReleasesReservationAndFailsSession() async throws {
        let fixture = SessionFixture()
        defer { fixture.cleanup() }
        fixture.coordinator.engineLoader = { _ in nil }
        let session = try await fixture.create()
        do {
            try await fixture.coordinator.startRecording(sessionID: session.id, clientID: fixture.clientID)
            XCTFail("missing engine started")
        } catch { XCTAssertEqual(error as? IntegrationError, .modelNotReady) }
        XCTAssertFalse(fixture.ownership.isBusy)
        XCTAssertEqual(try fixture.service.session(session.id, clientID: fixture.clientID)?.state, .failed)
    }

}

@MainActor
private final class SessionFixture {
    let suite = "InputSessionOwnershipTests-\(UUID())"
    let defaults: UserDefaults
    let settings: AppSettings
    let clientID = IntegrationClient.localHTTP(tokenID: "token").id
    let service: OpenTypeService
    let ownership = InputSessionOwnership()
    let coordinator: InputSessionCoordinator

    init() {
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
        settings.outputMode = .direct
        settings.useScreenContext = false
        let registry = IntegrationClientRegistry(defaults: defaults)
        registry.approve(.localHTTP(tokenID: "token"))
        service = OpenTypeService(
            settings: .init(developerInterfaceEnabled: true, httpToken: "token"), registry: registry
        )
        coordinator = InputSessionCoordinator(service: service, settings: settings, ownership: ownership)
        coordinator.speechActivityOverrideForTesting = { _ in true }
    }

    func create() async throws -> InputSession {
        try await service.createSession(
            InputSessionRequest(mode: .direct, language: .english, useScreenContext: false), clientID: clientID
        )
    }

    func cleanup() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
private final class SessionBarrier {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func entered() async { while continuation == nil { await Task.yield() } }
    func open() { continuation?.resume(); continuation = nil }
}

private final class SessionEngine: SpeechEngine, @unchecked Sendable {
    var isReady: Bool { true }
    var transcription: () async -> String = { "test" }
    func transcribe(audioURL: URL?, language: String?) async throws -> String { await transcription() }
}
