import Carbon
import XCTest
@testable import UtterPresentation

@MainActor
final class OverlayShortcutTests: XCTestCase {
    func testBindingsAreOneUseAndQueuedEventsCannotControlANewerSessionOrReceipt() throws {
        let registration = TestOverlayShortcutRegistration()
        let shortcuts = OverlayShortcuts(registration: registration)
        defer { shortcuts.close() }
        var actions: [OverlayShortcuts.Action] = []
        shortcuts.onAction = { actions.append($0) }
        let first = UUID(), second = UUID(), receipt = UUID()
        shortcuts.update(cancel: first, restore: nil)
        let staleID = try XCTUnwrap(registration.keys.first?.key)
        shortcuts.update(cancel: second, restore: nil)
        registration.press(staleID)
        XCTAssertTrue(actions.isEmpty)
        let currentID = try XCTUnwrap(registration.keys.first?.key)
        registration.press(currentID); registration.press(currentID)
        XCTAssertEqual(actions, [.cancel(second)])
        XCTAssertTrue(registration.keys.isEmpty)
        shortcuts.update(cancel: nil, restore: receipt)
        let restoreID = try XCTUnwrap(registration.keys.first?.key)
        registration.press(restoreID); registration.press(restoreID)
        XCTAssertEqual(actions, [.cancel(second), .restore(receipt)])
        shortcuts.update(cancel: nil, restore: UUID())
        let hiddenID = try XCTUnwrap(registration.keys.first?.key)
        shortcuts.update(cancel: nil, restore: nil)
        registration.press(hiddenID)
        XCTAssertEqual(actions.count, 2)
        shortcuts.close()
        shortcuts.update(cancel: first, restore: receipt)
        XCTAssertTrue(registration.closed)
        XCTAssertTrue(registration.keys.isEmpty)
    }

    func testRegistrationConflictIsNotAdvertisedOrDispatched() {
        let registration = TestOverlayShortcutRegistration()
        registration.rejectsRegistration = true
        let shortcuts = OverlayShortcuts(registration: registration)
        defer { shortcuts.close() }
        let id = UUID()
        var calls = 0
        shortcuts.onAction = { _ in calls += 1 }
        for _ in 0..<20 { shortcuts.update(cancel: id, restore: nil) }
        XCTAssertEqual(registration.attempts, 1)
        XCTAssertFalse(shortcuts.isRegistered(.cancel(id)))
        XCTAssertTrue(registration.keys.isEmpty)
        registration.press(1)
        XCTAssertEqual(calls, 0)
    }

    func testRealCarbonEventDecodingRejectsWrongSignatureAndKindsWithoutGlobalRegistration() throws {
        let registration = CarbonOverlayShortcuts()
        defer { registration.close() }
        var calls: [UInt32] = []
        registration.onPress = { calls.append($0) }
        for (signature, kind, expected) in [(CarbonOverlayShortcuts.signature, UInt32(kEventHotKeyPressed), true),
            (UInt32(0), UInt32(kEventHotKeyPressed), false),
            (CarbonOverlayShortcuts.signature, UInt32(kEventHotKeyReleased), false)] {
            var event: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), kind, 0, 0, &event), noErr)
            let value = try XCTUnwrap(event)
            defer { ReleaseEvent(value) }
            var hotkey = EventHotKeyID(signature: signature, id: 42)
            XCTAssertEqual(SetEventParameter(value, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                MemoryLayout<EventHotKeyID>.size, &hotkey), noErr)
            XCTAssertEqual(registration.handle(value), expected ? noErr : OSStatus(eventNotHandledErr))
        }
        XCTAssertEqual(calls, [42])
        registration.close()
        XCTAssertNil(registration.onPress)
    }
}
