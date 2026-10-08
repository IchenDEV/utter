import Foundation
import XCTest
@testable import UtterContracts

final class ModelLocationLeaseTests: XCTestCase {
    func testFrozenMissingModelNeverQueriesNewPreferences() throws {
        let files = LocationFiles()
        let frozen = TextProcessingOptions(settings: SettingsValues()).freezingModelLocations(using: files)
        files.url = URL(fileURLWithPath: "/new/model")
        files.queries = 0
        let request = TextGenerationRequest(prompt: "", modelID: "model", frozenModel: frozen.modelVersions?.directory)
        XCTAssertThrowsError(try request.localModelURL(using: files)) {
            XCTAssertEqual($0 as? GenerationServiceError, .modelUnavailable)
        }
        XCTAssertEqual(files.queries, 0)
    }

    func testReplacingDirectoryInvalidatesFrozenRequestAndChangesCacheRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = root.appendingPathComponent("model")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        let original = ModelLocationLease(model)
        try FileManager.default.moveItem(at: model, to: root.appendingPathComponent("old"))
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        let published = ModelLocationLease(model)
        XCTAssertNotEqual(original.revision, published.revision)
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(published.isCurrent)
        XCTAssertThrowsError(try original.requireInstalledURL()) {
            XCTAssertEqual($0 as? GenerationServiceError, .modelChanged)
        }
        XCTAssertEqual(try published.requireInstalledURL(), model)
    }
}

private final class LocationFiles: ModelFilesService, @unchecked Sendable {
    var url: URL?
    var queries = 0
    func installedTextModelURL(_ id: String) -> URL? { queries += 1; return url }
    func installedSpeechModelURL(_ id: String) -> URL? { nil }
    func speechRequiredFiles(_ id: String) -> [String] { [] }
    func textModelIsComplete(at url: URL) -> Bool { false }
    func installedWhisperURL(_ id: String) -> URL? { nil }
    func whisperVariantURL(_ id: String) -> URL { URL(fileURLWithPath: "/unused") }
    func whisperModelIsComplete(at url: URL) -> Bool { false }
}
