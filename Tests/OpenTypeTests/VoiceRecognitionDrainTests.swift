import UtterMediaContracts
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
import XCTest
import UtterContracts
import UtterSession

@MainActor
final class VoiceRecognitionDrainTests: XCTestCase {
    func testCancellationDrainsRecognitionBeforeSessionOrMaintenanceCanReuseModel() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.engine.holdDrain = true
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let access = try fixture.runtime.service(ModelServices.resourceAccess)
        try driver.start(SessionIntent(input: .local))
        while driver.snapshot.phase != .recording { await Task.yield() }
        while !fixture.engine.preparing { await Task.yield() }
        driver.cancel()
        while !fixture.engine.draining { await Task.yield() }
        XCTAssertTrue(fixture.capture.recording.stopped)
        XCTAssertFalse(fixture.capture.recording.closed)
        var maintained = false
        let maintenance = Task { try await access.withAccess { maintained = true } }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(driver.snapshot.isBusy)
        XCTAssertFalse(maintained)
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .local)))
        fixture.engine.releaseDrain()
        await driver.stop()
        try await maintenance.value
        XCTAssertTrue(maintained)
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        try await fixture.runtime.stop()
    }
}
