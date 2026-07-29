import XCTest
@testable import OpenType

@MainActor
final class HotkeyManagerChordTests: XCTestCase {
    func testTranslationChordStartsAndStopsTranslation() {
        let (settings, cleanup) = makeChordSettings()
        defer { cleanup() }
        var events: [String] = []
        let manager = HotkeyManager(
            settings: settings,
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") }
        )

        manager.processPhysicalKeyState(
            primaryPressed: false,
            translationModifierPressed: true
        )
        manager.processPhysicalKeyState(
            primaryPressed: true,
            translationModifierPressed: true
        )
        manager.processPhysicalKeyState(
            primaryPressed: false,
            translationModifierPressed: true
        )

        XCTAssertEqual(events, ["start:translation", "stop:translation"])
    }

    func testTranslationChordWinsWhenModifierArrivesDuringGracePeriod() {
        let (settings, cleanup) = makeChordSettings()
        defer { cleanup() }
        var events: [String] = []
        let manager = HotkeyManager(
            settings: settings,
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") }
        )

        manager.processPhysicalKeyState(
            primaryPressed: true,
            translationModifierPressed: false
        )
        manager.processPhysicalKeyState(
            primaryPressed: true,
            translationModifierPressed: true
        )
        manager.processPhysicalKeyState(
            primaryPressed: false,
            translationModifierPressed: true
        )

        XCTAssertEqual(events, ["start:translation", "stop:translation"])
    }
}

private func makeChordSettings() -> (AppSettings, () -> Void) {
    let suiteName = "OpenTypeTests.HotkeyChord.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let settings = AppSettings(defaults: defaults)
    settings.activationMode = .longPress
    settings.hotkeyType = .fn
    settings.translationHotkeyModifier = .shift
    return (
        settings,
        { defaults.removePersistentDomain(forName: suiteName) }
    )
}
