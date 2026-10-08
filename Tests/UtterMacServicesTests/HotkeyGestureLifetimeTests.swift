import XCTest
import UtterContracts
@testable import UtterMacServices

final class HotkeyGestureLifetimeTests: XCTestCase {
    func testReleaseUsesActivationModeFromThePress() {
        var settings = SettingsValues()
        settings.activationMode = .longPress
        var stops = 0
        let controller = HotkeyActivationController(settings: { settings }, onStart: { _ in }, onStop: { _ in stops += 1 })
        controller.beginGesture(.dictation)
        settings.activationMode = .toggle
        controller.endGesture(.dictation)
        XCTAssertEqual(stops, 1)
    }

    func testResetStopsAnActiveToggleOnceAndAllowsAFreshGesture() {
        var settings = SettingsValues()
        settings.activationMode = .toggle
        var starts = 0
        var stops = 0
        let controller = HotkeyActivationController(
            settings: { settings }, onStart: { _ in starts += 1 }, onStop: { _ in stops += 1 }
        )
        controller.beginGesture(.dictation)
        controller.reset()
        controller.reset()
        controller.beginGesture(.translation)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(stops, 1)
    }
}
