import XCTest
import Foundation
import UtterContracts
@testable import UtterPresentation

final class SettingsRemoteMicPlacementTests: XCTestCase {
    private static let generalSettingsSource = "Sources/UtterPresentation/UI/GeneralSettingsView.swift"

    /// A source guard, not a rendering test: it only stops the controls coming back to General.
    func testGeneralSettingsDoesNotMentionTheRemoteMicControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(Self.generalSettingsSource)
        let source: String
        do { source = try String(contentsOf: url, encoding: .utf8) } catch {
            return XCTFail("Cannot read \(Self.generalSettingsSource) from \(url.path): \(error)")
        }
        for forbidden in ["remoteMicEnabled", "remoteMicGainDB", "remote_mic", "remoteState"] {
            XCTAssertFalse(source.contains(forbidden),
                "\(Self.generalSettingsSource) must not reference \(forbidden); the controls live in Integrations")
        }
    }

    func testHelpTextPointsAtGeneralNotAtAControlAbove() {
        for language in [UILanguage.english, .chinese] {
            let help = Loc.string("settings.remote_mic_help", language: language)
            let general = Loc.string("tab.general", language: language)
            XCTAssertTrue(help.contains(general), "\(language): help text should name the \(general) tab")
            XCTAssertFalse(help.localizedCaseInsensitiveContains("above"), "\(language): \(help)")
            XCTAssertFalse(help.contains("上方"), "\(language): \(help)")
        }
    }
}
