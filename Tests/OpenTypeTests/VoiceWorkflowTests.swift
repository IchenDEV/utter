import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterRuntime
import UtterSession

@MainActor
final class VoiceWorkflowTests: XCTestCase {
    func testCancelledPreparationDrainsBeforeModelMaintenanceOrAnotherSource() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.engine.holdPreparation = true
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let access = try fixture.runtime.service(ModelServices.resourceAccess)
        try driver.start(SessionIntent(input: .local))
        while !fixture.engine.preparing { await Task.yield() }
        var maintained = false
        let maintenance = Task { try await access.withAccess { maintained = true } }
        let stop = Task { await driver.stop() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(maintained)
        XCTAssertTrue(driver.snapshot.isBusy)
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .remote(token: 8))))
        fixture.engine.release()
        await stop.value
        try await maintenance.value
        XCTAssertTrue(maintained)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        try await fixture.runtime.stop()
    }

    func testCancelledAPIStartWaitDrainsPreparationBeforeReturning() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.engine.holdPreparation = true
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let driver = try fixture.runtime.service(SessionServices.execution)
        let credentials = try fixture.runtime.service(DataServices.credentials)
        credentials.update { $0.developerHTTPToken = "token" }
        let client = IntegrationClient.localHTTP(tokenID: "token")
        try fixture.runtime.service(IntegrationServices.clients).approve(client)
        let row = try await api.createSession(InputSessionRequest(), clientID: client.id)
        let start = Task { () -> Result<Void, Error> in
            do { try await api.startRecording(sessionID: row.id, clientID: client.id); return .success(()) }
            catch { return .failure(error) }
        }
        while !fixture.engine.preparing { await Task.yield() }
        start.cancel()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(driver.snapshot.isBusy)
        fixture.engine.release()
        switch await start.value {
        case .success: XCTFail("Cancelled start reported readiness")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertEqual(try api.session(row.id, clientID: client.id)?.state, .cancelled)
        try await fixture.runtime.stop()
    }

    func testCreatedFileJobFreezesPathsAndCredentialsBeforeActivation() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let driver = try fixture.runtime.service(SessionServices.execution)
        let clients = try fixture.runtime.service(IntegrationServices.clients)
        let credentials = try fixture.runtime.service(DataServices.credentials)
        let settings = try fixture.runtime.service(DataServices.settings)
        let client = IntegrationClient.localHTTP(tokenID: "original")
        credentials.update { $0.developerHTTPToken = "original"; $0.remoteAPIKey = "original-generation-key" }
        clients.approve(client)
        let borrowed = fixture.directory.appendingPathComponent("borrowed.wav")
        try Data("borrowed".utf8).write(to: borrowed)
        let oldURL = fixture.files.url
        let row = try await api.createSession(InputSessionRequest(language: .english), input: .file(borrowed), clientID: client.id)
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        fixture.files.url = fixture.directory.appendingPathComponent("later-model")
        credentials.update { $0.remoteAPIKey = "changed-generation-key" }
        settings.update { $0.inputLanguage = .chinese; $0.microphoneID = "later-device" }
        try await api.startRecording(sessionID: row.id, clientID: client.id)
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(driver.snapshot.phase, .completed)
        XCTAssertEqual(fixture.speechRequests.first?.modelFiles?.installedSpeechModelURL(""), oldURL)
        XCTAssertEqual(fixture.speechRequests.first?.selection.locale, InputLanguage.english.localeIdentifier)
        XCTAssertEqual(fixture.recipe.requests.first?.options.remoteAPIKey, "original-generation-key")
        XCTAssertEqual(fixture.recipe.requests.first?.options.modelLocations, .frozen(bundle: nil, directory: oldURL))
        XCTAssertEqual(fixture.engine.transcribed.compactMap { $0 }, [borrowed])
        XCTAssertEqual(try Data(contentsOf: borrowed), Data("borrowed".utf8))
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertEqual(try api.session(row.id, clientID: client.id)?.state, .completed)
        XCTAssertEqual(try fixture.runtime.service(DataServices.history).records.map(\.id), [row.id])
        try await fixture.runtime.stop()
    }

    func testUnavailableInputCancelsTheStopWaitAndClosesRecording() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        try driver.start(SessionIntent(input: .local))
        while driver.snapshot.phase != .recording { await Task.yield() }
        fixture.capture.callbacks?.inputUnavailable()
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        XCTAssertTrue(fixture.capture.recording.closed)
        XCTAssertTrue(fixture.engine.transcribed.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        try await fixture.runtime.stop()
    }

    func testRemoteCaptureFailureCannotFallBackToTheLocalMicrophone() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.capture.error = CaptureError.remoteUnavailable
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        try driver.start(SessionIntent(input: .remote(token: 27)))
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(fixture.capture.requests.map(\.source), [.remote(token: 27)])
        XCTAssertEqual(driver.snapshot.phase, .failed)
        XCTAssertTrue(fixture.engine.transcribed.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
        try await fixture.runtime.stop()
    }

    func testAcceptedPasteSurvivesCancellationAndHoldsModelLeaseThroughOutputCleanup() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.output.delivery.heldCommit = true
        fixture.output.delivery.heldClose = true
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let history = try fixture.runtime.service(DataServices.history)
        let access = try fixture.runtime.service(ModelServices.resourceAccess)
        let intent = SessionIntent(input: .local)
        try driver.start(intent)
        while driver.snapshot.phase != .recording { await Task.yield() }
        let stop = Task { await driver.stop() }
        while !fixture.output.delivery.committing { await Task.yield() }
        driver.cancel()
        var maintained = false
        let maintenance = Task { try await access.withAccess { maintained = true } }
        fixture.output.delivery.releaseCommit()
        while !fixture.output.delivery.closing { await Task.yield() }
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertTrue(driver.snapshot.isBusy)
        XCTAssertFalse(maintained)
        fixture.output.delivery.releaseClose()
        await stop.value
        try await maintenance.value
        XCTAssertEqual(driver.snapshot.phase, .completed)
        XCTAssertEqual(history.records.map(\.id), [intent.id])
        XCTAssertTrue(fixture.capture.recording.closed)
        XCTAssertEqual(fixture.output.requests.count, 1)
        try await fixture.runtime.stop()
    }
}
