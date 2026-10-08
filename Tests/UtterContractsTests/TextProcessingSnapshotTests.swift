import XCTest
@testable import UtterContracts

final class TextProcessingSnapshotTests: XCTestCase {
    func testOptionsKeepOneSettingsSnapshotAndExplicitProviderChoice() {
        var settings = SettingsValues()
        settings.llmModel = "original-model"
        settings.remoteModel = "original-remote"
        var options = TextProcessingOptions(settings: settings)
        options.textProviderID = "fixture.provider"
        settings.llmModel = "new-model"
        settings.remoteModel = "new-remote"
        XCTAssertEqual(options.llmModel, "original-model")
        XCTAssertEqual(options.remoteModel, "original-remote")
        XCTAssertEqual(options.textProviderID, "fixture.provider")
    }
}
