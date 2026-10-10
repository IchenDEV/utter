import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterSession
@testable import UtterIngress

@MainActor
final class RemoteSessionIngressTests: XCTestCase {
    func testReleaseDuringModelPreparationStopsTheOriginalCaptureWithoutRestartingIt() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.engine.holdPreparation = false; fixture.engine.release(); fixture.remove() }
        fixture.defaults.set(true, forKey: "remoteMicEnabled")
        fixture.engine.holdPreparation = true
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let remote = IngressRemote()
        let binding = RemoteSessionBinding(remote: remote, settings: try fixture.runtime.service(DataServices.settings),
            execution: execution, diagnostics: IngressDiagnostics())
        binding.start()
        remote.pressed?(42)
        let id = try XCTUnwrap(execution.snapshot.id)
        try await execution.waitForRecording(id)
        try await waitUntil { fixture.engine.preparing }
        remote.released?()
        try await waitUntil { fixture.capture.recording.finished }
        XCTAssertEqual(fixture.capture.requests.count, 1)
        XCTAssertTrue(execution.snapshot.isBusy)
        fixture.engine.release()
        _ = try await execution.waitForCompletion(id)
        XCTAssertEqual(execution.snapshot.phase, .completed)
        XCTAssertEqual(fixture.capture.requests.count, 1)
        XCTAssertEqual(fixture.engine.transcribed.count, 1)
        await binding.close()
        try await fixture.runtime.stop()
    }

    func testRemoteCallbacksAndDisposalCannotStopAnUnownedDesktopSession() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "remoteMicEnabled")
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let desktop = SessionIntent(input: .local)
        try execution.start(desktop)
        try await execution.waitForRecording(desktop.id)
        let remote = IngressRemote()
        let binding = RemoteSessionBinding(remote: remote, settings: try fixture.runtime.service(DataServices.settings),
            execution: execution, diagnostics: IngressDiagnostics())
        binding.start()
        let latePress = remote.pressed
        remote.pressed?(42)
        remote.released?()
        remote.stopped?()
        await binding.close()
        latePress?(99)
        XCTAssertEqual(execution.snapshot.id, desktop.id)
        XCTAssertTrue(execution.snapshot.isBusy)
        XCTAssertFalse(fixture.capture.recording.stopped)
        execution.cancel(desktop.id)
        await execution.stop(desktop.id)
        XCTAssertEqual(execution.snapshot.phase, .cancelled)
        try await fixture.runtime.stop()
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Expected ingress signal was not received", file: file, line: line)
                throw WaitFailure.timedOut
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    private enum WaitFailure: Error { case timedOut }
}

@MainActor
private final class IngressRemote: RemoteMicControlService {
    var diagnostics = RemoteMicDiagnostics()
    func reconnect() {}
    func observeDiagnostics(_ callback: @escaping (RemoteMicDiagnostics) -> Void) -> UUID { UUID() }
    var state: RemoteMicBridgeState = .idle
    var pressed: ((UInt64) -> Void)?
    var released: (() -> Void)?
    var stopped: (() -> Void)?
    func setEnabled(_ enabled: Bool) {}
    func setVoiceCallbacks(pressed: ((UInt64) -> Void)?, released: (() -> Void)?, stopped: (() -> Void)?) {
        self.pressed = pressed; self.released = released; self.stopped = stopped
    }
    func observe(_ callback: @escaping (RemoteMicBridgeState) -> Void) -> UUID { UUID() }
    func removeObserver(_ id: UUID) {}
}
private struct IngressDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
