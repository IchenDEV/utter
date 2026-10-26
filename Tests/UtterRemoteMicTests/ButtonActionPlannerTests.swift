import XCTest
import UtterContracts
@testable import UtterRemoteMic

final class ButtonActionPlannerTests: XCTestCase {
    private let fn = EventFlag.secondaryFn
    private let command = EventFlag.command

    private func inputs(
        _ action: ButtonAction, button: RemoteButton = .ok, showDesktop: KeyboardShortcut? = ButtonActionPlanner.standardShowDesktop
    ) -> [SyntheticInput] {
        ButtonActionPlanner.inputs(for: action, button: button, showDesktop: showDesktop)
    }

    // MARK: native emulation (Batch 0 table)

    func testNativeOfAKeyIsOneKeyPressWithTheFlagsMacOSAdds() {
        XCTAssertEqual(inputs(.native, button: .ok), [
            .key(code: 36, down: true, flags: 0, isModifier: false),
            .key(code: 36, down: false, flags: 0, isModifier: false),
        ])
        XCTAssertEqual(inputs(.native, button: .up), [
            .key(code: 126, down: true, flags: 0xA0_0000, isModifier: false),
            .key(code: 126, down: false, flags: 0xA0_0000, isModifier: false),
        ], "fn and numeric pad ride on the key event; no modifier key is pressed")
    }

    func testNativeOfAVolumeKeyIsAMediaKeyPressAndBackIsNothing() {
        XCTAssertEqual(inputs(.native, button: .volumeUp), [.media(key: 0, down: true), .media(key: 0, down: false)])
        XCTAssertEqual(inputs(.native, button: .volumeDown), [.media(key: 1, down: true), .media(key: 1, down: false)])
        XCTAssertEqual(inputs(.native, button: .back), [])
    }

    func testEveryButtonsNativeEmulationIsAtMostOnePress() {
        for button in RemoteButton.allCases {
            XCTAssertLessThanOrEqual(inputs(.native, button: button).count, 2, button.rawValue)
        }
    }

    // MARK: chords

    func testAChordPressesItsModifierThenTheKeyThenReleasesInReverse() {
        let copy = KeyChord(keyCode: 8, modifiers: [.command])
        XCTAssertEqual(inputs(.key(copy)), [
            .key(code: 55, down: true, flags: command, isModifier: true),
            .key(code: 8, down: true, flags: command, isModifier: false),
            .key(code: 8, down: false, flags: command, isModifier: false),
            .key(code: 55, down: false, flags: 0, isModifier: true),
        ])
    }

    func testSeveralModifiersAccumulateInAFixedOrderAndReleaseInReverse() {
        let chord = KeyChord(keyCode: 2, modifiers: [.command, .shift, .option, .control])
        let all = EventFlag.control | EventFlag.option | EventFlag.shift | EventFlag.command
        XCTAssertEqual(inputs(.key(chord)), [
            .key(code: 59, down: true, flags: EventFlag.control, isModifier: true),
            .key(code: 58, down: true, flags: EventFlag.control | EventFlag.option, isModifier: true),
            .key(code: 56, down: true, flags: EventFlag.control | EventFlag.option | EventFlag.shift, isModifier: true),
            .key(code: 55, down: true, flags: all, isModifier: true),
            .key(code: 2, down: true, flags: all, isModifier: false),
            .key(code: 2, down: false, flags: all, isModifier: false),
            .key(code: 55, down: false, flags: EventFlag.control | EventFlag.option | EventFlag.shift, isModifier: true),
            .key(code: 56, down: false, flags: EventFlag.control | EventFlag.option, isModifier: true),
            .key(code: 58, down: false, flags: EventFlag.control, isModifier: true),
            .key(code: 59, down: false, flags: 0, isModifier: true),
        ])
    }

    func testAKeyWithoutModifiersIsJustDownAndUp() {
        XCTAssertEqual(inputs(.key(KeyChord(keyCode: 53))), [
            .key(code: 53, down: true, flags: 0, isModifier: false),
            .key(code: 53, down: false, flags: 0, isModifier: false),
        ])
    }

    func testTheFnFlagStaysOnEveryEventOfAChordWithoutBecomingAModifierKey() {
        let events = ButtonActionPlanner.chordInputs(code: 103, flags: fn | command)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0], .key(code: 55, down: true, flags: fn | command, isModifier: true))
        XCTAssertEqual(events[3], .key(code: 55, down: false, flags: fn, isModifier: true))
    }

    // MARK: built-in actions

    func testSystemKeysUseTheMeasuredMediaKeyNumbers() {
        let expected: [(SystemKey, UInt32)] = [
            (.volumeUp, 0), (.volumeDown, 1), (.mute, 7), (.playPause, 16), (.next, 17), (.previous, 18),
        ]
        XCTAssertEqual(expected.count, SystemKey.allCases.count)
        for (key, number) in expected {
            XCTAssertEqual(inputs(.system(key)), [.media(key: number, down: true), .media(key: number, down: false)])
        }
    }

    func testAppSwitcherIsCommandTabWithRealModifierEvents() {
        XCTAssertEqual(inputs(.appSwitcher), [
            .key(code: 55, down: true, flags: command, isModifier: true),
            .key(code: 48, down: true, flags: command, isModifier: false),
            .key(code: 48, down: false, flags: command, isModifier: false),
            .key(code: 55, down: false, flags: 0, isModifier: true),
        ])
    }

    func testShowDesktopIsF11WithFnByDefaultAndFollowsACustomShortcut() {
        XCTAssertEqual(inputs(.showDesktop), [
            .key(code: 103, down: true, flags: fn, isModifier: false),
            .key(code: 103, down: false, flags: fn, isModifier: false),
        ])
        let custom = KeyboardShortcut(keyCode: 2, flags: EventFlag.control)
        XCTAssertEqual(inputs(.showDesktop, showDesktop: custom).count, 4)
        XCTAssertEqual(inputs(.showDesktop, showDesktop: nil), [], "turned off in System Settings")
    }

    func testOpenAppIsOneNonKeyboardInput() {
        let result = inputs(.openApp(bundleID: "com.apple.Safari"))
        XCTAssertEqual(result, [.openApp(bundleID: "com.apple.Safari")])
        XCTAssertFalse(result[0].isKeyboard)
        XCTAssertTrue(SyntheticInput.media(key: 0, down: true).isKeyboard)
    }

    // MARK: the user's Show Desktop shortcut

    func testNoStoredEntryMeansTheSystemDefault() {
        XCTAssertEqual(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: nil), ButtonActionPlanner.standardShowDesktop)
        XCTAssertEqual(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["27": ["enabled": 1]]), ButtonActionPlanner.standardShowDesktop)
    }

    func testADisabledEntryTurnsTheActionOff() {
        XCTAssertNil(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": ["enabled": 0]]))
        XCTAssertNil(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": ["enabled": false]]))
    }

    func testACustomShortcutIsUsedAndOnlyShortcutBitsSurvive() {
        let entry: [String: Any] = ["enabled": 1, "value": ["parameters": [65_535, 2, 262_144 | 0x1F], "type": "standard"]]
        XCTAssertEqual(
            ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": entry]),
            KeyboardShortcut(keyCode: 2, flags: EventFlag.control)
        )
        let fnF11: [String: Any] = ["enabled": 1, "value": ["parameters": [65_535, 103, 8_388_608]]]
        XCTAssertEqual(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": fnF11]), ButtonActionPlanner.standardShowDesktop)
    }

    func testNoKeyAssignedOrAnUnreadableEntryIsHandledWithoutCrashing() {
        let unassigned: [String: Any] = ["enabled": 1, "value": ["parameters": [65_535, 65_535, 0]]]
        XCTAssertNil(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": unassigned]))
        let short: [String: Any] = ["enabled": 1, "value": ["parameters": [1, 2]]]
        XCTAssertEqual(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": short]), ButtonActionPlanner.standardShowDesktop)
        XCTAssertEqual(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": "garbage"]), ButtonActionPlanner.standardShowDesktop)
        let negative: [String: Any] = ["enabled": 1, "value": ["parameters": [65_535, -4, -1]]]
        XCTAssertNil(ButtonActionPlanner.resolveShowDesktop(symbolicHotKeys: ["36": negative]))
    }
}
