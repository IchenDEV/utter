import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterRuntime
@testable import UtterSession

@MainActor
final class SessionAPIExecutionTests: XCTestCase {
    func testStopRecordingUsesReservedExecutionAndReturnsOnlyAfterDrain() async throws {
        let fixture = try APIExecutionFixture()
        defer { fixture.remove() }
        fixture.job.waitsForStop = true
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let execution = try fixture.runtime.service(SessionServices.execution)
        let row = try await api.createSession(InputSessionRequest(), clientID: fixture.client.id)
        try await api.startRecording(sessionID: row.id, clientID: fixture.client.id)
        let stop = Task { try await api.stopRecording(sessionID: row.id, clientID: fixture.client.id) }
        while !fixture.job.closing { await Task.yield() }
        XCTAssertTrue(execution.snapshot.isBusy)
        fixture.job.finishClose()
        let result = try await stop.value
        XCTAssertEqual(result.session.state, .completed)
        XCTAssertEqual(result.text, "final")
        XCTAssertEqual(fixture.factory.intents.count, 1)
        try await fixture.runtime.stop()
    }

    func testCreatedReservationBindsOneSourceWithoutAnotherFactoryCall() async throws {
        let fixture = try APIExecutionFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let driver = try fixture.runtime.service(SessionServices.execution)
        let row = try await api.createSession(InputSessionRequest(), clientID: fixture.client.id)
        XCTAssertEqual(fixture.factory.intents.map(\.input), [.unselected])
        let file = URL(fileURLWithPath: "/later-upload.wav")
        try driver.activate(row.id, input: .file(file))
        XCTAssertEqual(fixture.job.boundInput, .file(file))
        XCTAssertThrowsError(try driver.activate(row.id, input: .local))
        while !fixture.job.entered { await Task.yield() }
        fixture.job.release()
        while !fixture.job.closing { await Task.yield() }
        fixture.job.finishClose()
        let result = try await driver.waitForCompletion(row.id)
        XCTAssertEqual(result.text, "final")
        XCTAssertEqual(fixture.factory.intents.count, 1)
        try await fixture.runtime.stop()
    }

    func testPresetFileReservationRejectsSwitchingToMicrophone() async throws {
        let fixture = try APIExecutionFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        try driver.reserve(SessionIntent(input: .file(URL(fileURLWithPath: "/preset.wav"))))
        XCTAssertThrowsError(try driver.activate(try XCTUnwrap(driver.snapshot.id), input: .local))
        XCTAssertFalse(fixture.job.entered)
        driver.cancel()
        while !fixture.job.closing { await Task.yield() }
        fixture.job.finishClose()
        await driver.stop()
        try await fixture.runtime.stop()
    }

    func testFileReservationBlocksDesktopAndCommitsAcceptedDeliveryAfterRevocation() async throws {
        let fixture = try APIExecutionFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let driver = try fixture.runtime.service(SessionServices.execution)
        let history = try fixture.runtime.service(DataServices.history)
        let credentials = try fixture.runtime.service(DataServices.credentials)
        let source = SessionInput.file(URL(fileURLWithPath: "/borrowed.wav"))
        let row = try await api.createSession(InputSessionRequest(), input: source, clientID: fixture.client.id)
        XCTAssertEqual(fixture.factory.intents.map(\.input), [source])
        XCTAssertFalse(fixture.job.entered)
        XCTAssertThrowsError(try api.commitSession(sessionID: row.id, clientID: fixture.client.id, finalText: "external", record: {})) {
            XCTAssertEqual($0 as? IntegrationError, .invalidSessionState)
        }
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .local))) {
            XCTAssertEqual($0 as? IntegrationError, .busy)
        }
        try await api.startRecording(sessionID: row.id, clientID: fixture.client.id)
        while !fixture.job.entered { await Task.yield() }
        XCTAssertEqual(try api.session(row.id, clientID: fixture.client.id)?.state, .processing)
        XCTAssertEqual(try api.snapshotEvents(sessionID: row.id, clientID: fixture.client.id).map(\.type),
                       [.sessionCreated, .recordingStarted, .transcriptPartial, .audioReceived, .transcriptFinal, .processingStarted])
        credentials.update { $0.developerHTTPToken = "rotated" }
        driver.cancel()
        fixture.job.release()
        while !fixture.job.closing { await Task.yield() }
        XCTAssertTrue(driver.snapshot.isBusy)
        XCTAssertTrue(history.records.isEmpty)
        credentials.update { $0.developerHTTPToken = "token" }
        var observations = 0
        let check: () -> Void = {
            XCTAssertEqual(driver.snapshot.phase, .completed)
            XCTAssertFalse(driver.snapshot.isBusy)
            XCTAssertEqual(try? api.session(row.id, clientID: fixture.client.id)?.state, .completed)
            XCTAssertEqual(history.records.map(\.id), [row.id])
            XCTAssertEqual(try? api.snapshotEvents(sessionID: row.id, clientID: fixture.client.id).suffix(2).map(\.type),
                           [.textFinal, .sessionCompleted])
            observations += 1
        }
        _ = history.observe(check)
        _ = try api.subscribeEvents(sessionID: row.id, clientID: fixture.client.id) { _ in check() }
        fixture.job.finishClose()
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(observations, 3)
        XCTAssertEqual(fixture.factory.intents.count, 1)
        try await fixture.runtime.stop()
    }

    func testCancellingCreatedAPIReservationPublishesOnlyAfterDrain() async throws {
        let fixture = try APIExecutionFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let driver = try fixture.runtime.service(SessionServices.execution)
        let row = try await api.createSession(InputSessionRequest(), clientID: fixture.client.id)
        let cancel = Task { try await api.cancel(sessionID: row.id, clientID: fixture.client.id) }
        while !fixture.job.closing { await Task.yield() }
        XCTAssertFalse(fixture.job.entered)
        XCTAssertEqual(try api.session(row.id, clientID: fixture.client.id)?.state, .created)
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .remote(token: 2))))
        fixture.job.finishClose()
        try await cancel.value
        XCTAssertEqual(try api.session(row.id, clientID: fixture.client.id)?.state, .cancelled)
        XCTAssertEqual(try api.snapshotEvents(sessionID: row.id, clientID: fixture.client.id).map(\.type),
                       [.sessionCreated, .sessionCancelled])
        try await fixture.runtime.stop()
    }
}

@MainActor
private struct APIExecutionFixture {
    let suite = "SessionAPIExecution-" + UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let client = IntegrationClient.localHTTP(tokenID: "token")
    let job = APIHeldDeliveryJob()
    let factory: APIWorkflowFactory
    let runtime: PluginRuntime
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "developerInterfaceEnabled")
        factory = APIWorkflowFactory(job: job)
        let workflow = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.workflow", provides: [SessionServices.workflows.reference])) { [factory] context, _ in
            try context.provide(SessionServices.workflows, value: factory)
        }
        let plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.credentials(), DataPlugins.notifications(),
                       DataPlugins.integrationClients(defaults: defaults),
                       DataPlugins.history(directoryURL: directory, reportError: { _ in }),
                       workflow, SessionPlugins.execution(), SessionPlugins.api()]
        runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
    }
    func start() async throws {
        try await runtime.start(["data.settings", "data.credentials", "data.notifications", "data.integration-clients",
                                 "data.history", "fixture.workflow", "session.execution", "session.api"].map { PluginSelection($0) })
        try runtime.service(DataServices.credentials).update { $0.developerHTTPToken = "token" }
        try runtime.service(IntegrationServices.clients).approve(client)
    }
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class APIWorkflowFactory: SessionWorkflowFactory {
    let job: APIHeldDeliveryJob
    var intents: [SessionIntent] = []
    init(job: APIHeldDeliveryJob) { self.job = job }
    func make(_ intent: SessionIntent) throws -> any SessionJob { intents.append(intent); return job }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {}
}

@MainActor
private final class APIHeldDeliveryJob: SessionJob {
    var waitsForStop = false
    var boundInput: SessionInput?
    var entered = false
    var closing = false
    private var work: CheckedContinuation<Void, Never>?
    private var cleanup: CheckedContinuation<Void, Never>?
    func bind(input: SessionInput) throws { boundInput = input }
    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        entered = true
        control.update(phase: .recording, transcript: "raw")
        if waitsForStop { try await control.waitForStop() }
        control.update(phase: .transcribing, transcript: "")
        control.update(phase: .processing, transcript: "raw")
        if !waitsForStop { await withCheckedContinuation { work = $0 } }
        return SessionCompletion(transcript: "raw", text: "final", acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, confirmation: .targetValue)
        ), record: InputRecord(rawText: "raw", processedText: "final", wasProcessed: true))
    }
    func revoke() {}
    func close() async {
        closing = true
        await withCheckedContinuation { cleanup = $0 }
    }
    func release() { work?.resume(); work = nil }
    func finishClose() { cleanup?.resume(); cleanup = nil }
}
