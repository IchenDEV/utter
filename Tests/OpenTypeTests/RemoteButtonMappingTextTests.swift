import AppKit
import Foundation
import XCTest
import UtterContracts
import UtterPresentation

final class RemoteButtonMappingTextTests: XCTestCase {
    private let states: [RemoteButtonMappingState] = [
        .off, .waitingForRemote, .needsPermission(canAsk: true), .needsPermission(canAsk: false),
        .needsRestart, .active, .conflict, .failed,
    ]

    private func assertLocalized(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        for language in [UILanguage.english, .chinese] {
            XCTAssertNotEqual(Loc.string(key, language: language), key, "\(key) missing in \(language)", file: file, line: line)
        }
        XCTAssertNotEqual(
            Loc.string(key, language: .english), Loc.string(key, language: .chinese),
            "\(key) is not translated", file: file, line: line
        )
    }

    func testEveryStateHasLocalizedTextInBothLanguagesAndOnlyProblemsNeedAttention() throws {
        let keys = Set(states.map(RemoteButtonMappingText.stateKey))
        XCTAssertEqual(keys.count, 7, "the two permission variants share one state label")
        for key in keys { assertLocalized(key) }
        let attention = states.filter(RemoteButtonMappingText.needsAttention)
        XCTAssertEqual(attention, [.needsPermission(canAsk: true), .needsPermission(canAsk: false), .needsRestart, .conflict, .failed])
        for state in attention { assertLocalized(try XCTUnwrap(RemoteButtonMappingText.detailKey(state))) }
        for state in [RemoteButtonMappingState.off, .waitingForRemote, .active] {
            XCTAssertNil(RemoteButtonMappingText.detailKey(state))
        }
        XCTAssertNotEqual(
            RemoteButtonMappingText.detailKey(.needsPermission(canAsk: true)),
            RemoteButtonMappingText.detailKey(.needsPermission(canAsk: false))
        )
    }

    func testOnlyAPermissionStateOffersAnActionAndAskingDependsOnWhetherTheSystemWillPrompt() {
        XCTAssertEqual(RemoteButtonMappingText.permissionAction(.needsPermission(canAsk: true)), .allow)
        XCTAssertEqual(RemoteButtonMappingText.permissionAction(.needsPermission(canAsk: false)), .openSettings)
        for state in [RemoteButtonMappingState.off, .waitingForRemote, .needsRestart, .active, .conflict, .failed] {
            XCTAssertNil(RemoteButtonMappingText.permissionAction(state))
        }
        XCTAssertTrue(RemoteButtonMappingText.inputMonitoringSettingsURL.absoluteString.hasSuffix("Privacy_ListenEvent"))
    }

    func testEveryButtonTriggerAndSystemKeyHasLocalizedText() {
        for button in RemoteButton.allCases { assertLocalized(RemoteButtonMappingText.buttonKey(button)) }
        for trigger in ButtonTrigger.allCases { assertLocalized(RemoteButtonMappingText.triggerKey(trigger)) }
        for key in SystemKey.allCases { assertLocalized(RemoteButtonMappingText.systemKey(key)) }
        let others = [
            "remote_buttons.title", "remote_buttons.help", "remote_buttons.needs_remap", "remote_buttons.status",
            "remote_buttons.allow", "remote_buttons.open_settings", "remote_buttons.grid.header", "remote_buttons.notes",
            "remote_buttons.action.native", "remote_buttons.action.media", "remote_buttons.action.show_desktop",
            "remote_buttons.action.app_switcher", "remote_buttons.action.shortcut", "remote_buttons.action.open_app",
            "remote_buttons.action.app_missing", "remote_buttons.recorder.prompt", "remote_buttons.recorder.hint",
            "remote_buttons.recorder.cancel", "remote_buttons.restore_defaults", "remote_buttons.pick_app",
        ]
        for key in others { assertLocalized(key) }
    }

    func testChordsAreNamedLikeMacOSMenusWithModifiersInTheStandardOrder() {
        XCTAssertEqual(KeyChordText.describe(KeyChord(keyCode: 48, modifiers: .command)), "⌘⇥")
        XCTAssertEqual(KeyChordText.describe(KeyChord(keyCode: 21, modifiers: [.shift, .command])), "⇧⌘4")
        XCTAssertEqual(
            KeyChordText.describe(KeyChord(keyCode: 49, modifiers: [.command, .shift, .option, .control])), "⌃⌥⇧⌘Space"
        )
        XCTAssertEqual(KeyChordText.describe(KeyChord(keyCode: 123)), "←")
        XCTAssertEqual(KeyChordText.describe(KeyChord(keyCode: 103)), "F11")
        XCTAssertEqual(KeyChordText.describe(KeyChord(keyCode: 0)), "A")
        XCTAssertEqual(KeyChordText.describe(KeyChord(keyCode: 200)), "Key 200")
    }

    func testEveryNamedKeyCodeIsDistinct() {
        let codes = (0...127).map { KeyChordText.keyName(UInt16($0)) }.filter { !$0.hasPrefix("Key ") }
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertGreaterThanOrEqual(codes.count, 60)
    }

    func testRecordedFlagsKeepOnlyTheFourModifiers() {
        let chord = KeyChordText.chord(keyCode: 36, flags: [.command, .capsLock, .numericPad, .function, .shift])
        XCTAssertEqual(chord, KeyChord(keyCode: 36, modifiers: [.command, .shift]))
        XCTAssertEqual(KeyChordText.chord(keyCode: 36, flags: []), KeyChord(keyCode: 36))
        XCTAssertEqual(KeyChordText.chord(keyCode: 36, flags: [.capsLock, .function, .numericPad]), KeyChord(keyCode: 36))
    }

    func testCellSummariesNameTheAction() {
        Loc.use(.english)
        let names = ["com.apple.Safari": "Safari"]
        func summary(_ action: ButtonAction) -> String {
            RemoteButtonMappingText.summary(of: action, appName: { names[$0] })
        }
        XCTAssertEqual(summary(.native), "Default")
        XCTAssertEqual(summary(.key(KeyChord(keyCode: 33, modifiers: .command))), "⌘[")
        XCTAssertEqual(summary(.system(.playPause)), "Play / Pause")
        XCTAssertEqual(summary(.showDesktop), "Show Desktop")
        XCTAssertEqual(summary(.appSwitcher), "App Switcher")
        XCTAssertEqual(summary(.openApp(bundleID: "com.apple.Safari")), "Safari")
        XCTAssertEqual(summary(.openApp(bundleID: "com.example.gone")), "App not found")
    }
}
