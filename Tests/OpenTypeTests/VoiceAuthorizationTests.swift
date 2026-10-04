import UtterPresentationContracts
import UtterData
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
import UtterMediaContracts
import UtterRuntime
import UtterSession

@MainActor
final class VoiceAuthorizationTests: XCTestCase {
    func testRevocationReleasesACreatedReservationWithoutPreparingAnEngine() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let driver = try fixture.runtime.service(SessionServices.execution)
        let client = try approve(fixture)
        let clients = try fixture.runtime.service(IntegrationServices.clients)
        let row = try await api.createSession(InputSessionRequest(), clientID: client.id)
        clients.revoke(clientID: client.id)
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        clients.approve(client)
        XCTAssertEqual(try api.session(row.id, clientID: client.id)?.state, .cancelled)
        try await fixture.runtime.stop()
    }

    func testPrincipalChangesCloseRecordingBeforeRecognitionOrOutput() async throws {
        for change in ["client", "interface", "token"] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            try await fixture.start()
            let api = try fixture.runtime.service(SessionServices.api)
            let driver = try fixture.runtime.service(SessionServices.execution)
            let client = try approve(fixture)
            let row = try await api.createSession(InputSessionRequest(), clientID: client.id)
            try await api.startRecording(sessionID: row.id, clientID: client.id)
            XCTAssertEqual(driver.snapshot.phase, .recording)
            switch change {
            case "client": try fixture.runtime.service(IntegrationServices.clients).revoke(clientID: client.id)
            case "interface": try fixture.runtime.service(DataServices.settings).update { $0.developerInterfaceEnabled = false }
            default: try fixture.runtime.service(DataServices.credentials).update { $0.developerHTTPToken = "rotated" }
            }
            while driver.snapshot.isBusy { await Task.yield() }
            XCTAssertEqual(driver.snapshot.phase, .cancelled, change)
            XCTAssertTrue(fixture.capture.recording.closed, change)
            XCTAssertTrue(fixture.engine.transcribed.isEmpty, change)
            XCTAssertTrue(fixture.output.requests.isEmpty, change)
            XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty, change)
            try await fixture.runtime.stop()
        }
    }

    private func approve(_ fixture: VoiceWorkflowFixture) throws -> IntegrationClient {
        let client = IntegrationClient.localHTTP(tokenID: "token")
        try fixture.runtime.service(DataServices.credentials).update { $0.developerHTTPToken = "token" }
        try fixture.runtime.service(IntegrationServices.clients).approve(client)
        return client
    }
}
