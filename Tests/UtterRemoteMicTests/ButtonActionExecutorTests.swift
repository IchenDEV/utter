import XCTest
import UtterContracts
@testable import UtterRemoteMic

@MainActor
private final class FakePoster: SyntheticInputPosting {
    private(set) var posted: [SyntheticInput] = []
    var failing: (SyntheticInput) -> Bool = { _ in false }
    var knownApps: Set<String> = ["com.apple.Safari"]

    func post(_ input: SyntheticInput) -> Bool {
        if failing(input) { return false }
        if case .openApp(let id) = input, !knownApps.contains(id) { return false }
        posted.append(input)
        return true
    }
}

@MainActor
final class ButtonActionExecutorTests: XCTestCase {
    private let poster = FakePoster()
    private var secure = false
    private var showDesktop: KeyboardShortcut? = ButtonActionPlanner.standardShowDesktop
    private var logs: [String] = []

    private func executor() -> ButtonActionExecutor {
        ButtonActionExecutor(
            poster: poster, isSecureInput: { [unowned self] in secure },
            showDesktopShortcut: { [unowned self] in showDesktop }, log: { [unowned self] in logs.append($0) }
        )
    }

    private func run(_ action: ButtonAction, button: RemoteButton = .ok, trigger: ButtonTrigger = .single) {
        executor().perform(ButtonCommand(button: button, trigger: trigger, action: action))
    }

    // MARK: exact event counts

    func testEachActionPostsExactlyItsEvents() {
        let cases: [(ButtonAction, RemoteButton, Int)] = [
            (.native, .ok, 2), (.native, .volumeUp, 2), (.native, .back, 0),
            (.key(KeyChord(keyCode: 8, modifiers: [.command])), .ok, 4),
            (.key(KeyChord(keyCode: 53)), .ok, 2),
            (.system(.playPause), .ok, 2), (.showDesktop, .ok, 2), (.appSwitcher, .ok, 4),
            (.openApp(bundleID: "com.apple.Safari"), .ok, 1),
        ]
        for (action, button, count) in cases {
            let before = poster.posted.count
            run(action, button: button)
            XCTAssertEqual(poster.posted.count - before, count, "\(action) on \(button)")
        }
    }

    func testAPerformedActionLogsOneLineWithIdentifiersOnly() {
        run(.system(.mute), button: .menu, trigger: .long)
        XCTAssertEqual(logs, ["[RemoteButtons] menu long -> system"])
    }

    func testNativeOfBackSaysThereIsNothingToPost() {
        run(.native, button: .back)
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertEqual(logs, ["[RemoteButtons] back single -> native: nothing to post"])
    }

    // MARK: secure input

    func testSecureInputDropsEveryKeyboardShapedAction() {
        secure = true
        let actions: [(ButtonAction, RemoteButton)] = [
            (.native, .ok), (.native, .volumeUp), (.key(KeyChord(keyCode: 8, modifiers: [.command])), .ok),
            (.system(.volumeUp), .ok), (.showDesktop, .ok), (.appSwitcher, .ok),
        ]
        for (action, button) in actions { run(action, button: button) }
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertEqual(logs.count, actions.count)
        XCTAssertTrue(logs.allSatisfy { $0.hasSuffix("dropped, secure input is on") })
    }

    func testOpeningAnAppIsNotKeyboardInputSoSecureInputDoesNotBlockIt() {
        secure = true
        run(.openApp(bundleID: "com.apple.Safari"))
        XCTAssertEqual(poster.posted, [.openApp(bundleID: "com.apple.Safari")])
    }

    func testSecureInputIsReadAtTheMomentOfThePress() {
        run(.system(.volumeUp))
        secure = true
        run(.system(.volumeUp))
        secure = false
        run(.system(.volumeUp))
        XCTAssertEqual(poster.posted.count, 4)
    }

    // MARK: failures stay quiet

    func testAnUnknownBundleIdFailsQuietlyWithoutNamingTheApp() {
        run(.openApp(bundleID: "com.secret.Unknown"))
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertEqual(logs, ["[RemoteButtons] ok single -> openApp: could not be performed"])
        XCTAssertFalse(logs.joined().contains("secret"))
    }

    func testAFailedKeyStillReleasesTheModifiersThatWerePressed() {
        poster.failing = { input in
            if case .key(_, _, _, false) = input { return true }
            return false
        }
        run(.key(KeyChord(keyCode: 8, modifiers: [.command, .shift])))
        XCTAssertEqual(poster.posted, [
            .key(code: 56, down: true, flags: EventFlag.shift, isModifier: true),
            .key(code: 55, down: true, flags: EventFlag.shift | EventFlag.command, isModifier: true),
            .key(code: 55, down: false, flags: EventFlag.shift, isModifier: true),
            .key(code: 56, down: false, flags: 0, isModifier: true),
        ], "no modifier is left held and the failed key is not retried")
        XCTAssertEqual(logs, ["[RemoteButtons] ok single -> key: could not be performed"])
    }

    func testAFailureOfTheVeryFirstInputPostsNothingMore() {
        poster.failing = { _ in true }
        run(.system(.volumeUp))
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertEqual(logs, ["[RemoteButtons] ok single -> system: could not be performed"])
    }

    func testShowDesktopTurnedOffInSystemSettingsPostsNothing() {
        showDesktop = nil
        run(.showDesktop)
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertEqual(logs, ["[RemoteButtons] ok single -> showDesktop: nothing to post"])
    }

    func testLogsNeverContainKeysOrApps() {
        run(.key(KeyChord(keyCode: 9, modifiers: [.command])))
        run(.openApp(bundleID: "com.apple.Safari"))
        let text = logs.joined(separator: "\n")
        XCTAssertFalse(text.contains("Safari"))
        XCTAssertFalse(text.contains("keyCode"))
    }
}
