import AppKit
import XCTest
import UtterContracts
@testable import UtterPresentation

@MainActor
final class ShortcutCaptureTests: XCTestCase {
    private var captured: [KeyChord] = []
    private var cancels = 0

    private func view() -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = { [unowned self] in captured.append($0) }
        view.onCancel = { [unowned self] in cancels += 1 }
        return view
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], repeats: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "x", charactersIgnoringModifiers: "x", isARepeat: repeats, keyCode: code
        ))
    }

    func testAKeyWithModifiersIsCaptured() throws {
        let view = view()
        view.keyDown(with: try key(48, [.command, .shift]))
        XCTAssertEqual(captured, [KeyChord(keyCode: 48, modifiers: [.command, .shift])])
        XCTAssertEqual(cancels, 0)
    }

    func testEscapeAloneCancelsButEscapeWithAModifierIsAShortcut() throws {
        let view = view()
        view.keyDown(with: try key(53))
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(captured, [])
        view.keyDown(with: try key(53, .command))
        XCTAssertEqual(captured, [KeyChord(keyCode: 53, modifiers: .command)])
        XCTAssertEqual(cancels, 1)
    }

    func testAutoRepeatIsIgnoredSoOneHoldRecordsOnce() throws {
        let view = view()
        view.keyDown(with: try key(0, [], repeats: false))
        view.keyDown(with: try key(0, [], repeats: true))
        XCTAssertEqual(captured.count, 1)
    }

    func testCommandKeyEquivalentsAreTakenInsteadOfReachingTheMenuBar() throws {
        let view = view()
        XCTAssertTrue(view.performKeyEquivalent(with: try key(12, .command)))
        XCTAssertEqual(captured, [KeyChord(keyCode: 12, modifiers: .command)])
    }
}
