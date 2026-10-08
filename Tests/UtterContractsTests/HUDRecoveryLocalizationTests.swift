import XCTest
import UtterContracts

final class HUDRecoveryLocalizationTests: XCTestCase {
    func testRecoveryActionsHaveEnglishAndChineseLabels() {
        for language in [UILanguage.english, .chinese] {
            for key in ["common.close", "hud.open_models", "hud.open_permissions"] {
                let label = Loc.string(key, language: language)
                XCTAssertFalse(label.isEmpty)
                XCTAssertNotEqual(label, key)
            }
        }
    }
}
