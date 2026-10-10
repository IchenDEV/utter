import UtterMediaContracts
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
@testable import UtterMacServices
import UtterPresentationContracts
import UtterContracts
import XCTest
@testable import UtterPresentation

@MainActor
final class HotkeyManagerChordTests: XCTestCase {
    func testTranslationChordStartsAndStopsTranslation() {
        let (settings, cleanup) = makeChordSettings()
        defer { cleanup() }
        var events: [String] = []
        let manager = HotkeyManager(
            settings: { settings.snapshot },
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") },
            onPromote: { _ in events.append("promote"); return true },
            log: UtterContracts.Log(service: TestDiagnostics.service), markAccessibilityPrompted: {}
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

    func testLateModifierPromotesImmediateDictationWithoutRestartingCapture() {
        let (settings, cleanup) = makeChordSettings()
        defer { cleanup() }
        var events: [String] = []
        let manager = HotkeyManager(
            settings: { settings.snapshot },
            onStart: { events.append("start:\($0)") },
            onStop: { events.append("stop:\($0)") },
            onPromote: { _ in events.append("promote"); return true },
            log: UtterContracts.Log(service: TestDiagnostics.service), markAccessibilityPrompted: {}
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

        XCTAssertEqual(events, ["start:dictation", "promote", "stop:translation"])
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
