import UtterPresentationContracts
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterRuntime
import UtterSession

@MainActor
final class VoiceWorkflowTests: XCTestCase {
    func testSelectedIndustryVocabularyReachesTheEffectiveSpeechProvider() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let settings = try fixture.runtime.service(DataServices.settings)
        settings.update { $0.outputMode = .direct; $0.industryLexicon = .technology }
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local)
        try driver.start(intent)
        try await driver.waitForRecording(intent.id)
        driver.requestStop(intent.id)
        _ = try await driver.waitForCompletion(intent.id)
        XCTAssertTrue(fixture.engine.vocabulary.contains("Kubernetes"))
        XCTAssertTrue(fixture.engine.vocabulary.contains("Redis"))
        try await fixture.runtime.stop()
    }
    func testUnavailableMicrophoneSettlesAsFailureAfterCaptureAndRecognitionDrain() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        try driver.start(SessionIntent(input: .local))
        while driver.snapshot.phase != .recording { await Task.yield() }
        fixture.capture.callbacks?.inputUnavailable()
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(driver.snapshot.phase, .failed)
        XCTAssertEqual(driver.snapshot.error, AudioCaptureStartFailure.noUsableInput.localizedDescription)
        XCTAssertTrue(fixture.capture.recording.stopped)
        XCTAssertTrue(fixture.capture.recording.closed)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        try await fixture.runtime.stop()
    }

    func testMicrophonePermissionFailureSkipsModelPreparationAndOutput() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.capture.error = CaptureError.startFailed(.permissionDenied)
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local)
        try driver.start(intent)
        do { _ = try await driver.waitForCompletion(intent.id); XCTFail("Denied microphone reported readiness") }
        catch { XCTAssertEqual(error as? CaptureError, .startFailed(.permissionDenied)) }
        XCTAssertEqual(driver.snapshot.error, AudioCaptureStartFailure.permissionDenied.localizedDescription)
        XCTAssertFalse(fixture.engine.preparing)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        try await fixture.runtime.stop()
    }

    func testCaptureFinishesDuringColdPreparationAndPromotesOneJobWithFrozenChoices() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.engine.holdPreparation = true
        fixture.engine.isReady = false
        try await fixture.start()
        let settings = try fixture.runtime.service(DataServices.settings)
        settings.update { $0.outputMode = .direct; $0.translationTargetLanguage = .english; $0.inputLanguage = .english }
        let frozenModel = settings.values.llmModel
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local)
        try driver.start(intent)
        while !fixture.engine.preparing { await Task.yield() }
        XCTAssertEqual(driver.snapshot.phase, .recording)
        XCTAssertEqual(fixture.capture.requests.count, 1)
        settings.update { $0.translationTargetLanguage = .japanese; $0.llmModel = "later-model"; $0.inputLanguage = .chinese }
        XCTAssertTrue(driver.promoteToTranslation(intent.id, reason: .recording))
        let stop = Task { await driver.stop() }
        while !fixture.capture.recording.finished { await Task.yield() }
        XCTAssertFalse(driver.promoteToTranslation(intent.id, reason: .recording))
        XCTAssertFalse(fixture.capture.recording.closed)
        XCTAssertTrue(fixture.engine.transcribed.isEmpty)
        fixture.engine.isReady = true
        fixture.engine.release()
        await stop.value
        XCTAssertEqual(driver.snapshot.id, intent.id)
        XCTAssertEqual(driver.snapshot.phase, .completed)
        XCTAssertEqual(fixture.speechRequests.count, 1)
        XCTAssertEqual(fixture.capture.requests.count, 1)
        XCTAssertEqual(fixture.engine.transcribed, [URL(fileURLWithPath: "/captured.wav")])
        XCTAssertEqual(fixture.recipe.requests.last?.mode, .translation(.english))
        XCTAssertEqual(fixture.recipe.requests.last?.options.llmModel, frozenModel)
        XCTAssertEqual(fixture.recipe.requests.last?.options.inputLanguage, .english)
        XCTAssertTrue(fixture.capture.recording.closed)
        try await fixture.runtime.stop()
    }

    func testDesktopDeliveryReceivesFrozenClipboardPolicyThroughReplacementProvider() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.recipe.generationOutcome = .fallback
        try await fixture.start()
        let settings = try fixture.runtime.service(DataServices.settings)
        settings.update { $0.allowClipboardPaste = false }
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .text("Synthetic dictation"))
        try driver.reserve(intent)
        settings.update { $0.allowClipboardPaste = true }
        try driver.activate(intent.id)
        _ = try await driver.waitForCompletion(intent.id)
        XCTAssertEqual(fixture.output.requests.count, 1)
        XCTAssertFalse(try XCTUnwrap(fixture.output.requests.first).allowsClipboardPaste)
        XCTAssertEqual(driver.snapshot.deliveryStatus, .inserted)
        XCTAssertEqual(driver.snapshot.generationOutcome, .fallback)
        try await fixture.runtime.stop()
    }

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
        driver.cancel()
        let stop = Task { await driver.stop() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(maintained)
        XCTAssertTrue(driver.snapshot.isBusy)
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .remote(token: 8))))
        fixture.engine.release()
        await stop.value
        try await maintenance.value
        XCTAssertTrue(maintained)
        XCTAssertEqual(fixture.capture.requests.count, 1)
        XCTAssertTrue(fixture.capture.recording.closed)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        try await fixture.runtime.stop()
    }

    func testAPIStartReportsActualCaptureWhilePreparationContinuesAndCancellationStillDrains() async throws {
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
        switch await start.value {
        case .success: break
        case .failure(let error): XCTFail("Capture should already be running: \(error)")
        }
        driver.cancel()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(driver.snapshot.isBusy)
        fixture.engine.release()
        await driver.stop()
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        XCTAssertEqual(fixture.capture.requests.count, 1)
        XCTAssertTrue(fixture.capture.recording.closed)
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
        XCTAssertEqual(driver.snapshot.phase, .failed)
        XCTAssertEqual(driver.snapshot.error, AudioCaptureStartFailure.noUsableInput.localizedDescription)
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
        XCTAssertEqual(try fixture.runtime.service(SessionServices.outputs).snapshot.recentText, driver.snapshot.text)
        XCTAssertTrue(fixture.capture.recording.closed)
        XCTAssertEqual(fixture.output.requests.count, 1)
        try await fixture.runtime.stop()
    }
}
