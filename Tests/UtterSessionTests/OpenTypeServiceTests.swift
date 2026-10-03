import UtterData
import UtterContracts
import Foundation
import XCTest
@testable import UtterSession
@MainActor
final class OpenTypeServiceTests: XCTestCase {
    func testCreateSessionFailsWhenDeveloperInterfaceDisabled() async {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: false, httpToken: "token"),
            registry: store.registry
        )

        await assertThrowsIntegrationError(.developerInterfaceDisabled) {
            try await service.createSession(request(), clientID: clientID)
        }
    }

    func testCreateSessionFailsForUnauthorizedClient() async {
        let store = registry()
        defer { store.cleanup() }
        let service = OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token"),
            registry: store.registry
        )

        await assertThrowsIntegrationError(.unauthorizedClient) {
            try await service.createSession(request(), clientID: clientID)
        }
    }

    func testCreateSessionEmitsCreatedEvent() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)

        let session = try await service.createSession(request(), clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID), session)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .sessionCreated)
        XCTAssertEqual(events.first?.sessionID, session.id)
        XCTAssertEqual(events.first?.sequence, 1)
        XCTAssertNotNil(store.registry.client(id: clientID)?.lastUsedAt)
    }

    func testOnlyOneActiveSessionCanRecord() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let first = try await service.createSession(request(), clientID: clientID)
        try await service.startRecording(sessionID: first.id, clientID: clientID)

        await assertThrowsIntegrationError(.busy) {
            try await service.createSession(request(), clientID: clientID)
        }
        XCTAssertEqual(try service.session(first.id, clientID: clientID)?.state, .recording)
    }

    func testCancelSessionTransitionsToTerminalState() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        try await service.cancel(sessionID: session.id, clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .cancelled)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(events.map(\.type), [.sessionCreated, .sessionCancelled])
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testStartRecordingIncrementsEventSequence() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        try await service.startRecording(sessionID: session.id, clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .recording)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(events.map(\.type), [.sessionCreated, .recordingStarted])
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testCompleteSessionReleasesBusyAndEmitsFinalEvents() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)
        try await service.startRecording(sessionID: session.id, clientID: clientID)
        try await service.beginProcessing(sessionID: session.id, clientID: clientID)

        try await service.completeSession(sessionID: session.id, clientID: clientID, finalText: "done")

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .completed)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(
            events.map(\.type),
            [.sessionCreated, .recordingStarted, .processingStarted, .textFinal, .sessionCompleted]
        )
        XCTAssertEqual(events.map(\.sequence), [1, 2, 3, 4, 5])
        XCTAssertEqual(events.first(where: { $0.type == .textFinal })?.text, "done")

        let nextSession = try await service.createSession(request(), clientID: clientID)
        XCTAssertEqual(nextSession.state, .created)
    }

    func testFailSessionReleasesBusyAndEmitsFailureEvent() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)
        try await service.startRecording(sessionID: session.id, clientID: clientID)

        try await service.failSession(sessionID: session.id, clientID: clientID, error: .modelNotReady)

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .failed)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(events.map(\.type), [.sessionCreated, .recordingStarted, .sessionFailed])
        XCTAssertEqual(events.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(events.last?.error, IntegrationError.modelNotReady.payload)

        let nextSession = try await service.createSession(request(), clientID: clientID)
        XCTAssertEqual(nextSession.state, .created)
    }

    func testCancelNoOpsForMissingAndTerminalSessions() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        try await service.cancel(sessionID: UUID(), clientID: clientID)
        try await service.cancel(sessionID: session.id, clientID: clientID)
        try await service.cancel(sessionID: session.id, clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .cancelled)
        XCTAssertEqual(
            try service.snapshotEvents(sessionID: session.id, clientID: clientID).map(\.type),
            [.sessionCreated, .sessionCancelled]
        )
    }

    func testOtherApprovedClientCannotStartOwnedSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        approveOtherLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            try await service.startRecording(sessionID: session.id, clientID: otherClientID)
        }
    }

    func testOtherApprovedClientCannotCancelOwnedSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        approveOtherLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            try await service.cancel(sessionID: session.id, clientID: otherClientID)
        }
        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .created)
    }

    func testOtherApprovedClientCannotReadOwnedSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        approveOtherLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            _ = try service.session(session.id, clientID: otherClientID)
        }
        await assertThrowsIntegrationError(.unauthorizedClient) {
            _ = try service.snapshotEvents(sessionID: session.id, clientID: otherClientID)
        }
    }

    func testClientWithoutStreamEventsCannotReadSnapshotEvents() async throws {
        let store = registry()
        defer { store.cleanup() }
        store.registry.approve(recordOnlyClient)
        let service = OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "record-only"),
            registry: store.registry
        )
        let session = try await service.createSession(request(), clientID: recordOnlyClient.id)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            _ = try service.snapshotEvents(sessionID: session.id, clientID: recordOnlyClient.id)
        }
    }

    func testSubscribeEventsReturnsSnapshotAndReceivesLiveEvents() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        var received: [InputSessionEvent] = []
        let subscription = try service.subscribeEvents(sessionID: session.id, clientID: clientID) { event in
            received.append(event)
        }

        XCTAssertEqual(subscription.snapshot.map(\.type), [.sessionCreated])
        try service.emitTranscriptPartial(sessionID: session.id, clientID: clientID, text: "hel")
        try service.emitTranscriptFinal(sessionID: session.id, clientID: clientID, text: "hello")
        service.unsubscribeEvents(sessionID: session.id, subscriberID: subscription.id)
        try service.emitTranscriptPartial(sessionID: session.id, clientID: clientID, text: "ignored")

        XCTAssertEqual(received.map(\.type), [.transcriptPartial, .transcriptFinal])
        XCTAssertEqual(received.map(\.text), ["hel", "hello"])
    }

    func testSettingsProviderIsReadForEachCreateSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        var settings = IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token")
        let service = OpenTypeService(settingsProvider: { settings }, registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)
        try await service.cancel(sessionID: session.id, clientID: clientID)

        settings.developerInterfaceEnabled = false

        await assertThrowsIntegrationError(.developerInterfaceDisabled) {
            try await service.createSession(request(), clientID: clientID)
        }
    }

    func testHTTPTokenResetRejectsStaleLocalHTTPClient() async throws {
        let store = registry()
        defer { store.cleanup() }
        store.registry.approve(IntegrationClient.localHTTP(tokenID: "old"))
        store.registry.approve(IntegrationClient.localHTTP(tokenID: "new"))
        var settings = IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "old")
        let service = OpenTypeService(settingsProvider: { settings }, registry: store.registry)
        let oldClientID = IntegrationClient.localHTTP(tokenID: "old").id
        let newClientID = IntegrationClient.localHTTP(tokenID: "new").id
        let oldSession = try await service.createSession(request(), clientID: oldClientID)
        try await service.cancel(sessionID: oldSession.id, clientID: oldClientID)

        settings.httpToken = "new"

        await assertThrowsIntegrationError(.unauthorizedClient) {
            try await service.createSession(request(), clientID: oldClientID)
        }
        let newSession = try await service.createSession(request(), clientID: newClientID)
        XCTAssertEqual(newSession.state, .created)
    }

}
