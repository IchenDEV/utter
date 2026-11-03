import AppKit
import XCTest
import UtterContracts
import UtterData
import UtterPresentationContracts
@testable import UtterPresentation

/// How long the HUD stays after a session ends: unconfirmed insertions leave on their own, errors that
/// need action do not, and an older timer never hides a newer session's overlay.
@MainActor
final class DesktopOverlayDwellTests: XCTestCase {
    private func unconfirmed(_ id: UUID = UUID()) -> SessionExecutionSnapshot {
        SessionExecutionSnapshot(id: id, phase: .failed, text: "今天确认 3 件事。", error: L("delivery.unconfirmed"), deliveryStatus: .uncertain)
    }

    func testUnconfirmedNoticeLeavesAfterTheDwell() async throws {
        let rig = try Rig(self)
        rig.host.project(unconfirmed())
        XCTAssertTrue(rig.overlay.visible)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(rig.overlay.visible, "It must not leave before the dwell")
        try await rig.waitUntil { !$0.visible }
        XCTAssertEqual(rig.overlay.hides, 1)
    }

    func testNewSessionKeepsItsOverlayWhenAnOlderTimerFires() async throws {
        let rig = try Rig(self)
        let old = UUID()
        rig.host.project(unconfirmed(old))
        // Bypass `host.project` so the older timer is still armed when the newer session appears.
        rig.host.state.project(SessionExecutionSnapshot(id: UUID(), phase: .recording, isBusy: true))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(rig.overlay.visible)
        XCTAssertEqual(rig.overlay.hides, 0, "The timer of session \(old) must not hide a newer session")
    }

    func testStartingARecordingReplacesTheNoticeImmediately() async throws {
        let rig = try Rig(self)
        rig.host.project(unconfirmed())
        rig.host.project(SessionExecutionSnapshot(id: UUID(), phase: .recording, isBusy: true))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(rig.overlay.visible)
        XCTAssertEqual(rig.overlay.hides, 0)
    }

    func testErrorsThatNeedActionStayUntilClosed() async throws {
        let rig = try Rig(self)
        rig.host.project(SessionExecutionSnapshot(id: UUID(), phase: .failed, error: L("pipeline.model_load_failed"), recoveryAction: .models))
        rig.host.project(SessionExecutionSnapshot(id: UUID(), phase: .failed, text: "text", error: L("delivery.unavailable"), deliveryStatus: .notDelivered))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(rig.overlay.visible)
        XCTAssertEqual(rig.overlay.hides, 0)
        rig.host.dismissOverlay()
        XCTAssertFalse(rig.overlay.visible)
    }

    func testConfirmedInsertionStillLeavesQuickly() async throws {
        let rig = try Rig(self, dwell: .seconds(60))
        rig.host.project(SessionExecutionSnapshot(id: UUID(), phase: .completed, text: "text", deliveryStatus: .inserted))
        XCTAssertTrue(rig.overlay.visible)
        try await rig.waitUntil(timeout: .seconds(3)) { !$0.visible }
    }

    func testMenuBarReopensTheNoticeAndItLeavesAgain() async throws {
        let rig = try Rig(self)
        rig.host.project(unconfirmed())
        try await rig.waitUntil { !$0.visible }

        rig.host.reshowUnconfirmedNotice()
        XCTAssertTrue(rig.overlay.visible)
        try await rig.waitUntil { !$0.visible }
        XCTAssertEqual(rig.overlay.hides, 2)
    }

    func testMenuBarDoesNotShowANoticeWhenNothingIsUnconfirmed() throws {
        let rig = try Rig(self)
        rig.host.project(SessionExecutionSnapshot(id: UUID(), phase: .completed, text: "text", deliveryStatus: .inserted))
        rig.host.hideOverlay()
        let shows = rig.overlay.shows
        rig.host.reshowUnconfirmedNotice()
        XCTAssertEqual(rig.overlay.shows, shows)
    }
}

@MainActor
private final class FakeOverlay: OverlayPresentationService {
    private(set) var visible = false
    private(set) var shows = 0
    private(set) var hides = 0
    func show(context: PresentationContext, targetApp: NSRunningApplication?) { visible = true; shows += 1 }
    func hide() { visible = false; hides += 1 }
}

@MainActor
private final class Rig {
    let host: NativeDesktopHost
    let overlay = FakeOverlay()

    init(_ test: XCTestCase, dwell: Duration = .milliseconds(120)) throws {
        let suite = "DesktopOverlayDwell-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = SettingsStore(defaults: defaults)
        host = NativeDesktopHost(catalog: PresentationRegistry(), settings: settings,
            credentials: SettingsCredentialsService(settings: settings), execution: nil, outputs: nil,
            overlay: overlay, icons: nil, diagnostics: DwellDiagnostics(), isCurrent: { true },
            shortcutRegistration: TestOverlayShortcutRegistration())
        host.uncertainDwell = dwell
        let host = host
        test.addTeardownBlock { @MainActor in host.close(); defaults.removePersistentDomain(forName: suite) }
    }

    func waitUntil(timeout: Duration = .seconds(2), _ condition: (FakeOverlay) -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(overlay) {
            guard ContinuousClock.now < deadline else { return XCTFail("Timed out waiting for the overlay state") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct DwellDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
