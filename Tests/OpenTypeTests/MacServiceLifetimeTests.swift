import AppKit
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterRuntime
@testable import UtterMacServices

@MainActor
final class MacServiceLifetimeTests: XCTestCase {
    func testScreenRevocationDrainsAndRejectsANonCooperativeCapture() async {
        let entered = MacLifetimeSignal()
        let release = MacLifetimeSignal()
        let closeEntered = MacLifetimeSignal()
        let service = ScopedScreenCapture(isCurrent: { true }, capture: { _, _ in
            entered.send()
            await release.wait()
            return .empty
        }, checkPermission: { true }, requestPermission: {})
        let capture = Task { try await service.capture(mode: .ocr) }
        await entered.wait()
        var closed = false
        let close = Task {
            service.revoke()
            closeEntered.send()
            await service.close()
            closed = true
        }
        await closeEntered.wait()
        XCTAssertFalse(closed)
        release.send()
        do { _ = try await capture.value; XCTFail("Revoked screen result was delivered") } catch {}
        await close.value
        XCTAssertTrue(closed)
    }

    func testColdScreenMetadataDoesNotCheckCaptureOrRequestPermissions() async {
        var calls = 0
        let service = ScopedScreenCapture(isCurrent: { true }, capture: { _, _ in calls += 1; return .empty },
            checkPermission: { calls += 1; return true }, requestPermission: { calls += 1 })
        XCTAssertEqual(calls, 0)
        service.revoke()
        service.requestPermission()
        do { _ = try await service.checkPermission(); XCTFail("Closed permission query was admitted") } catch {}
        await service.close()
        XCTAssertEqual(calls, 0)
    }

    func testHotkeyCloseCancelsThePendingChordAndRejectsLaterPhysicalEvents() async {
        var events = 0
        var settings = SettingsValues()
        settings.activationMode = .longPress
        let manager = HotkeyManager(settings: { settings }, onStart: { _ in events += 1 }, onStop: { _ in },
            log: Log(service: MacTestDiagnostics()), markAccessibilityPrompted: {})
        manager.processPhysicalKeyState(primaryPressed: true, translationModifierPressed: false)
        await manager.close()
        manager.processPhysicalKeyState(primaryPressed: true, translationModifierPressed: true)
        XCTAssertEqual(events, 0)
        XCTAssertTrue(manager.ownedTasks.isEmpty)
    }

    func testNativeClipboardCommitHasOneReceiptAndCannotReplayAfterUserCopiesSomethingElse() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let backend = NativeOutputBackend(log: Log(service: MacTestDiagnostics()), isCurrent: { true }, pasteboard: pasteboard)
        let service = ScopedOutputService(isCurrent: { true }, execute: backend.deliver)
        let request = DeliveryRequest(id: UUID(), command: .clipboard("output"))
        let delivery = try service.prepare(request, isSessionCurrent: { true })
        let receipt = await delivery.commit()
        XCTAssertEqual(receipt.disposition, .accepted)
        XCTAssertEqual(receipt.effect, .clipboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "output")
        await delivery.close()
        pasteboard.clearContents()
        pasteboard.setString("later user copy", forType: .string)
        let replay = try service.prepare(request, isSessionCurrent: { true })
        _ = await replay.commit()
        XCTAssertEqual(pasteboard.string(forType: .string), "later user copy")
        await service.close()
    }

    func testFinalClipboardBarrierRejectsALostTargetAndRestoresPreviousBytes() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("previous", forType: .string)
        let worker = TextInserter(log: Log(service: MacTestDiagnostics()))
        var current = true
        var pastes = 0
        worker.canCommit = { current }
        let task = Task {
            await worker.insertViaClipboard(text: "prepared", pasteboard: pasteboard) {
                pastes += 1
                return true
            }
        }
        while pasteboard.string(forType: .string) != "prepared" { await Task.yield() }
        current = false
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }
}

@MainActor
private final class MacLifetimeSignal {
    private var sent = false
    private var continuation: CheckedContinuation<Void, Never>?
    func send() { sent = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if sent { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

private struct MacTestDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
