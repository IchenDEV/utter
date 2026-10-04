import Foundation
import XCTest
@testable import UtterContracts

final class ProviderCapabilitiesTests: XCTestCase {
    func testExplicitLocalBindingOverridesRemoteLegacyFlags() {
        var settings = SettingsValues()
        settings.useRemoteLLM = true
        settings.localLLMBackend = .espresso
        let options = TextProcessingOptions(settings: settings).selecting(ProviderDescriptor(id: "replacement.local", displayName: "Local"))
        XCTAssertFalse(options.useRemoteLLM)
        XCTAssertEqual(options.localLLMBackend, .mlx)
        XCTAssertEqual(options.textProviderID, "replacement.local")
    }

    func testExplicitRemoteBindingUsesItsOwnRequestKind() {
        let options = TextProcessingOptions(settings: SettingsValues()).selecting(
            ProviderDescriptor(id: "replacement.remote", displayName: "Remote", modelLocation: .remote))
        XCTAssertTrue(options.useRemoteLLM)
        XCTAssertEqual(options.textProviderID, "replacement.remote")
    }

    func testMissingAndAvailableModelLocationsBothRemainFrozen() {
        let files = MutableCapabilityFiles()
        let original = TextProcessingOptions(settings: SettingsValues()).freezingModelLocations(using: files)
        files.url = URL(fileURLWithPath: "/later-model")
        XCTAssertEqual(original.modelLocations, .frozen(bundle: nil, directory: nil))
        let available = TextProcessingOptions(settings: SettingsValues()).freezingModelLocations(using: files)
        files.url = URL(fileURLWithPath: "/new-root/model")
        XCTAssertEqual(available.modelLocations, .frozen(bundle: nil, directory: URL(fileURLWithPath: "/later-model")))
    }
}

private final class MutableCapabilityFiles: ModelFilesService, @unchecked Sendable {
    var url: URL?
    func installedTextModelURL(_ id: String) -> URL? { url }
    func installedSpeechModelURL(_ id: String) -> URL? { nil }
    func speechRequiredFiles(_ id: String) -> [String] { [] }
    func textModelIsComplete(at url: URL) -> Bool { false }
    func installedWhisperURL(_ id: String) -> URL? { nil }
    func whisperVariantURL(_ id: String) -> URL { URL(fileURLWithPath: "/unused") }
    func whisperModelIsComplete(at url: URL) -> Bool { false }
}
