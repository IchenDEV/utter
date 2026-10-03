import XCTest
@testable import UtterContracts

final class SpeechSelectionTests: XCTestCase {
    func testExplicitProviderBindingOverridesTheLegacyAliasWithoutChangingTheFrozenSettings() {
        var settings = SettingsValues()
        settings.speechEngine = .qwen3
        settings.qwenASRModel = "synthetic-model"
        let selection = SpeechSelection(settings: settings, modelPath: "/tmp/synthetic", providerID: "speech.replacement")
        settings.speechEngine = .apple
        settings.qwenASRModel = "changed"
        XCTAssertEqual(selection.providerID, "speech.replacement")
        XCTAssertEqual(selection.model, "synthetic-model")
        XCTAssertEqual(selection.modelPath, "/tmp/synthetic")
        XCTAssertEqual(selection.type, .qwen3)
    }

    func testUnrelatedProviderCredentialsAreExcludedFromSpeechSelection() {
        var settings = SettingsValues()
        settings.speechEngine = .apple
        settings.volcAppKey = "synthetic-app-key"
        settings.volcAccessKey = "synthetic-access-key"
        let selection = SpeechSelection(settings: settings, inputLanguage: .english)
        XCTAssertEqual(selection.locale, "en-US")
        XCTAssertEqual(selection.providerID, "apple")
        XCTAssertEqual(selection.appKey, "")
        XCTAssertEqual(selection.accessKey, "")
        XCTAssertEqual(selection.resourceID, "")
    }
}
