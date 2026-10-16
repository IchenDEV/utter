import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterSession
@testable import UtterIngress

@MainActor
final class HotkeySessionBindingTests: XCTestCase {
    func testReleaseBeforeDisclosureConsentRetiresTheSameIntentWithoutStartingCapture() async throws {
        let fixture = try BindingFixture()
        defer { fixture.remove() }
        fixture.factory.requiredConsent = consent()
        fixture.binding.start()
        let id = UUID()
        fixture.hotkeys.captureID = id
        fixture.hotkeys.start?(.dictation)
        XCTAssertEqual(fixture.execution.snapshot.id, id)
        XCTAssertEqual(fixture.execution.snapshot.remoteDisclosure?.selectedText, "private selection 👩🏽‍💻")
        XCTAssertTrue(fixture.execution.snapshot.isBusy)
        XCTAssertEqual(fixture.factory.job.runs, 0)
        fixture.hotkeys.stop?(.dictation)
        XCTAssertEqual(fixture.execution.snapshot.phase, .cancelled)
        XCTAssertNil(fixture.execution.snapshot.remoteDisclosure)
        XCTAssertThrowsError(try fixture.execution.authorizeRemoteDisclosure(id))
        XCTAssertEqual(fixture.factory.job.runs, 0)
        XCTAssertEqual(fixture.factory.intents.count, 1)
        await fixture.binding.close(); await fixture.execution.close()
    }

    func testContinueWhileHeldStartsOneSameIntentAndNormalReleaseFinalizesIt() async throws {
        let fixture = try BindingFixture()
        defer { fixture.remove() }
        let approved = consent()
        fixture.factory.requiredConsent = approved
        fixture.binding.start()
        let id = UUID()
        fixture.hotkeys.captureID = id
        fixture.hotkeys.start?(.dictation)
        XCTAssertEqual(fixture.factory.job.runs, 0)
        try fixture.execution.authorizeRemoteDisclosure(id)
        XCTAssertThrowsError(try fixture.execution.authorizeRemoteDisclosure(id))
        try await fixture.execution.waitForRecording(id)
        XCTAssertEqual(fixture.factory.job.runs, 1)
        XCTAssertEqual(fixture.factory.intents.map(\.id), [id, id])
        XCTAssertEqual(fixture.factory.intents.last?.input, .local)
        XCTAssertEqual(fixture.factory.intents.last?.remoteSelectionConsent, approved)
        fixture.hotkeys.stop?(.dictation)
        let result = try await fixture.execution.waitForCompletion(id)
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(fixture.factory.job.runs, 1)
        await fixture.binding.close(); await fixture.execution.close()
    }

    func testDisclosureCancellationExpiryAndChangedTargetOrProviderHaveNoCapture() async throws {
        for change in 0..<4 {
            let fixture = try BindingFixture()
            defer { fixture.remove() }
            fixture.factory.requiredConsent = consent(expiresAt: Date().addingTimeInterval(change == 1 ? 0.02 : 120))
            let id = UUID()
            try fixture.execution.start(SessionIntent(id: id, input: .local))
            if change == 0 { fixture.execution.declineRemoteDisclosure(id) }
            else if change == 1 { try await Task.sleep(for: .milliseconds(60)) }
            else if change == 2 { fixture.factory.targetCurrent = false }
            else { fixture.factory.requiredConsent = consent(baseURL: "https://changed.example.test/v1") }
            XCTAssertThrowsError(try fixture.execution.authorizeRemoteDisclosure(id))
            XCTAssertEqual(fixture.factory.job.runs, 0)
            XCTAssertNil(fixture.execution.snapshot.remoteDisclosure)
            XCTAssertFalse(fixture.execution.snapshot.isBusy)
            await fixture.binding.close(); await fixture.execution.close()
        }
    }

    private func consent(baseURL: String = "https://model.example.test/v1", expiresAt: Date = Date().addingTimeInterval(120)) -> SelectionEditRemoteConsent {
        SelectionEditRemoteConsent(selectedText: "private selection 👩🏽‍💻", providerID: "generation.remote",
            providerBaseURL: baseURL, expiresAt: expiresAt)
    }

    func testCallbacksFreezeCaptureIdentityAndStopTimeBeforeDraining() async throws {
        let fixture = try BindingFixture()
        defer { fixture.remove() }
        fixture.binding.start()
        let id = UUID()
        fixture.hotkeys.captureID = id
        fixture.hotkeys.start?(.dictation)
        XCTAssertEqual(fixture.factory.intents.map(\.id), [id])
        XCTAssertEqual(fixture.factory.intents.map(\.input), [.local])
        while fixture.execution.snapshot.phase != .recording { await Task.yield() }
        XCTAssertTrue(fixture.hotkeys.promote?(.recording) == true)
        XCTAssertEqual(fixture.execution.snapshot.mode, .translation(.english))
        fixture.hotkeys.eventTimestamp = .milliseconds(100)
        fixture.hotkeys.stop?(.translation)
        XCTAssertTrue(fixture.factory.job.control?.isStopped == true)
        fixture.hotkeys.captureID = UUID()
        fixture.hotkeys.eventTimestamp = .milliseconds(900)
        let result = try await fixture.execution.waitForCompletion(id)
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.performance?.releaseToTerminalMilliseconds, 100)
        XCTAssertEqual(fixture.factory.intents.count, 1)
        await fixture.binding.close()
        await fixture.execution.close()
    }

    func testStaleStopCancelAndPromotionCannotControlAnotherSession() async throws {
        let fixture = try BindingFixture()
        defer { fixture.remove() }
        fixture.binding.start()
        let desktop = SessionIntent(input: .text("Other session"))
        try fixture.execution.start(desktop)
        while fixture.execution.snapshot.phase != .recording { await Task.yield() }
        fixture.hotkeys.captureID = UUID()
        fixture.hotkeys.start?(.dictation)
        fixture.hotkeys.stop?(.dictation)
        fixture.hotkeys.cancel?()
        XCTAssertFalse(fixture.hotkeys.promote?(.recording) ?? true)
        XCTAssertTrue(fixture.execution.snapshot.isBusy)
        XCTAssertFalse(fixture.factory.job.control?.isStopped ?? true)
        await fixture.binding.close()
        XCTAssertTrue(fixture.execution.snapshot.isBusy)
        fixture.execution.requestStop(desktop.id, at: nil)
        _ = try await fixture.execution.waitForCompletion(desktop.id)
        await fixture.execution.close()
    }
}

@MainActor
private final class BindingFixture {
    let suite = "HotkeySessionBinding-" + UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let hotkeys = BindingHotkeys()
    let factory = BindingWorkflows()
    let execution: SessionDriver
    let binding: HotkeySessionBinding
    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        let notifications = StateNotifications()
        let history = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in }, notifications: notifications)
        execution = SessionDriver(workflows: factory, history: history, notifications: notifications, now: { .milliseconds(200) })
        binding = HotkeySessionBinding(hotkeys: hotkeys, execution: execution,
            settings: SettingsStore(defaults: defaults), diagnostics: BindingLog())
    }
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class BindingHotkeys: HotkeyControlService {
    var captureID: UUID?
    var eventTimestamp: Duration?
    var start: ((HotkeyAction) -> Void)?
    var stop: ((HotkeyAction) -> Void)?
    var promote: ((HotkeyPromotion) -> Bool)?
    var cancel: (() -> Void)?
    func setEnabled(_ enabled: Bool) {}
    func setCallbacks(start: ((HotkeyAction) -> Void)?, stop: ((HotkeyAction) -> Void)?,
                      promote: ((HotkeyPromotion) -> Bool)?, cancel: (() -> Void)?) {
        self.start = start; self.stop = stop; self.promote = promote; self.cancel = cancel
    }
}
@MainActor
private final class BindingWorkflows: SessionWorkflowFactory {
    var intents: [SessionIntent] = []
    let job = BindingJob()
    var requiredConsent: SelectionEditRemoteConsent?
    var targetCurrent = true
    func make(_ intent: SessionIntent) throws -> any SessionJob {
        intents.append(intent)
        if let requiredConsent, intent.remoteSelectionConsent != requiredConsent {
            throw SelectionEditRemoteDisclosureRequired(consent: requiredConsent, isTargetCurrent: { self.targetCurrent })
        }
        return job
    }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {}
}
@MainActor
private final class BindingJob: SessionJob {
    weak var control: (any SessionJobControl)?
    var runs = 0
    func promoteToTranslation() -> TextProcessingMode? { .translation(.english) }
    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        runs += 1
        self.control = control
        control.update(phase: .recording, transcript: "")
        try await control.waitForStop()
        return SessionCompletion(transcript: "raw", text: "final", acceptance: .returnedText)
    }
    func revoke() {}
    func close() async {}
}
private struct BindingLog: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
