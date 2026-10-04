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
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts

@MainActor
final class VoiceScreenFailureTests: XCTestCase {
    func testReplyScreenFailuresDoNotGenerateOrDeliver() async throws {
        for status in [ScreenContextSnapshot.Status.permissionDenied, .captureFailed, .recognitionFailed] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.screen.snapshot = ScreenContextSnapshot(text: "", image: nil, status: status)
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("帮我回复这封邮件"), mode: .command)
            try execution.start(intent)
            do {
                _ = try await execution.waitForCompletion(intent.id)
                XCTFail("A screen failure was reported as a successful reply")
            } catch { XCTAssertTrue(error is ScreenContextFailure) }
            XCTAssertEqual(execution.snapshot.phase, .failed)
            XCTAssertEqual(execution.snapshot.recoveryAction, status == .permissionDenied ? .screenPrivacy : nil)
            XCTAssertTrue(fixture.recipe.requests.isEmpty)
            XCTAssertTrue(fixture.output.requests.isEmpty)
            try await fixture.runtime.stop()
        }
    }

    func testExternalScreenOptOutPreventsCaptureEvenForCommand() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let client = IntegrationClient.localCLI(executablePath: "/fixture/cli")
        try fixture.runtime.service(IntegrationServices.clients).approve(client)
        let execution = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(clientID: client.id, input: .text("Reply to the message"),
            request: InputSessionRequest(useScreenContext: false), mode: .command)
        try execution.start(intent)
        _ = try await execution.waitForCompletion(intent.id)
        XCTAssertTrue(fixture.screen.requests.isEmpty)
        XCTAssertEqual(fixture.recipe.requests.count, 1)
        try await fixture.runtime.stop()
    }
}
