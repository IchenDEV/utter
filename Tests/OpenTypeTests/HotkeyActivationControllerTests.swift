import XCTest
@testable import OpenType

final class HotkeyActivationControllerTests: XCTestCase {
    func testLongPressKeepsTranslationActionThroughRelease() {
        let (settings, cleanup) = makeHotkeySettings()
        defer { cleanup() }
        settings.activationMode = .longPress
        var events: [String] = []
        let controller = HotkeyActivationController(
            settings: settings,
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") }
        )

        controller.beginGesture(.translation)
        controller.endGesture(.translation)

        XCTAssertEqual(events, ["start:translation", "stop:translation"])
    }

    func testToggleStopsTheActiveModeBeforeStartingAnother() {
        let (settings, cleanup) = makeHotkeySettings()
        defer { cleanup() }
        settings.activationMode = .toggle
        var events: [String] = []
        let controller = HotkeyActivationController(
            settings: settings,
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") }
        )

        controller.beginGesture(.translation)
        controller.endGesture(.translation)
        controller.beginGesture(.dictation)

        XCTAssertEqual(events, ["start:translation", "stop:translation"])
    }
}

private func makeHotkeySettings() -> (AppSettings, () -> Void) {
    let suiteName = "OpenTypeTests.Hotkey.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (
        AppSettings(defaults: defaults),
        { defaults.removePersistentDomain(forName: suiteName) }
    )
}
