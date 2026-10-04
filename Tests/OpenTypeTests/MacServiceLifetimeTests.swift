import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
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

    func testHotkeyCloseCancelsImmediateCaptureAndRejectsLaterPhysicalEvents() async {
        var events = 0
        var cancelled = 0
        var settings = SettingsValues()
        settings.activationMode = .longPress
        let manager = HotkeyManager(settings: { settings }, onStart: { _ in events += 1 }, onStop: { _ in },
            onCancel: { cancelled += 1 },
            log: Log(service: MacTestDiagnostics()), markAccessibilityPrompted: {})
        manager.processPhysicalKeyState(primaryPressed: true, translationModifierPressed: false)
        await manager.close()
        manager.processPhysicalKeyState(primaryPressed: true, translationModifierPressed: true)
        XCTAssertEqual(events, 1)
        XCTAssertEqual(cancelled, 1)
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
        XCTAssertEqual(receipt.status, .copied)
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
        var current = true
        var pastes = 0
        let result = await ClipboardPasteTransaction.paste("prepared", pasteboard: NativeDeliveryPasteboard(pasteboard),
            canCommit: { current }, mark: { _ in true }, postPaste: { pastes += 1; return true },
            confirm: { false }, beforePaste: { current = false })
        XCTAssertEqual(result.disposition, .uncertain)
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }

    func testNativePasteboardRestoresAllRepresentationsAfterConfirmedConsumption() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        let customType = NSPasteboard.PasteboardType("utter.synthetic.bytes")
        item.setString("previous", forType: .string)
        item.setData(Data([0, 1, 255]), forType: customType)
        pasteboard.writeObjects([item])
        let adapter = NativeDeliveryPasteboard(pasteboard)
        let original = adapter.snapshot()
        let result = await ClipboardPasteTransaction.paste("prepared", pasteboard: adapter,
            canCommit: { true }, mark: { _ in true }, postPaste: { true }, confirm: {
                XCTAssertEqual(adapter.text, "prepared")
                return true
            })
        XCTAssertEqual(result.confirmation, .targetValue)
        XCTAssertEqual(adapter.snapshot(), original)
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
