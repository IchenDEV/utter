import UtterMediaContracts
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
import UtterSession

@MainActor
final class VoiceFileBindingTests: XCTestCase {
    func testLateUploadBindsCreatedJobWithoutRecapturingConfigurationOrMicrophone() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let api = try fixture.runtime.service(SessionServices.api)
        let credentials = try fixture.runtime.service(DataServices.credentials)
        let settings = try fixture.runtime.service(DataServices.settings)
        credentials.update { $0.developerHTTPToken = "token"; $0.remoteAPIKey = "original" }
        let client = IntegrationClient.localHTTP(tokenID: "token")
        try fixture.runtime.service(IntegrationServices.clients).approve(client)
        let row = try await api.createSession(InputSessionRequest(language: .english), clientID: client.id)
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        credentials.update { $0.remoteAPIKey = "changed" }
        settings.update { $0.inputLanguage = .chinese }
        let upload = fixture.directory.appendingPathComponent("uploaded.wav")
        try Data("borrowed".utf8).write(to: upload)
        let result = try await api.processAudioFile(sessionID: row.id, clientID: client.id, audioURL: upload)
        XCTAssertEqual(result.session.state, .completed)
        XCTAssertEqual(result.transcript, "Hello world.")
        XCTAssertEqual(fixture.recipe.requests.first?.options.remoteAPIKey, "original")
        XCTAssertEqual(fixture.speechRequests.first?.selection.locale, InputLanguage.english.localeIdentifier)
        XCTAssertEqual(fixture.engine.transcribed.compactMap { $0 }, [upload])
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: upload.path))
        do {
            _ = try await api.processAudioFile(sessionID: row.id, clientID: client.id, audioURL: upload)
            XCTFail("A terminal session accepted a second source")
        } catch { XCTAssertEqual(error as? IntegrationError, .invalidSessionState) }
        try await fixture.runtime.stop()
    }
}
