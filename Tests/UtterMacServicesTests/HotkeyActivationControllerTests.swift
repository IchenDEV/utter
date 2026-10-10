import UtterContracts
import XCTest
@testable import UtterMacServices

final class HotkeyActivationControllerTests: XCTestCase {
    func testLongPressKeepsTranslationActionThroughRelease() {
        var settings = SettingsValues()
        settings.activationMode = .longPress
        var events: [String] = []
        let controller = HotkeyActivationController(
            settings: { settings },
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") }
        )

        controller.beginGesture(.translation)
        controller.endGesture(.translation)

        XCTAssertEqual(events, ["start:translation", "stop:translation"])
    }

    func testToggleStopsTheActiveModeBeforeStartingAnother() {
        var settings = SettingsValues()
        settings.activationMode = .toggle
        var events: [String] = []
        let controller = HotkeyActivationController(
            settings: { settings },
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") }
        )

        controller.beginGesture(.translation)
        controller.endGesture(.translation)
        controller.beginGesture(.dictation)

        XCTAssertEqual(events, ["start:translation", "stop:translation"])
    }
}
