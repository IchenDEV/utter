import Foundation
import XCTest
import UtterContracts

final class FrozenModelFilesTests: XCTestCase {
    func testChangingPreferencesCannotChangeFrozenPathsOrRequirements() {
        let source = FrozenFilesSource()
        let frozen = FrozenModelFiles(modelID: "model", using: source)
        source.url = URL(fileURLWithPath: "/later-model")
        source.required = ["later-weights"]
        XCTAssertEqual(frozen.installedSpeechModelURL("model")?.path, "/original-model")
        XCTAssertEqual(frozen.installedWhisperURL("model")?.path, "/original-model")
        XCTAssertEqual(frozen.whisperVariantURL("model").path, "/original-model")
        XCTAssertEqual(frozen.speechRequiredFiles("model"), ["weights"])
        XCTAssertNil(frozen.installedSpeechModelURL("unselected"))
        XCTAssertTrue(frozen.isCurrent)
        XCTAssertNotEqual(frozen.revision, FrozenModelFiles(modelID: "model", using: source).revision)
    }

    func testReplacingThePublishedDirectoryInvalidatesItsFrozenIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = FrozenFilesSource()
        source.url = directory.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: source.url, withIntermediateDirectories: true)
        let frozen = FrozenModelFiles(modelID: "model", using: source)
        XCTAssertTrue(frozen.isCurrent)
        try FileManager.default.moveItem(at: source.url, to: directory.appendingPathComponent("previous"))
        try FileManager.default.createDirectory(at: source.url, withIntermediateDirectories: true)
        XCTAssertFalse(frozen.isCurrent)
        XCTAssertNotEqual(frozen.revision, FrozenModelFiles(modelID: "model", using: source).revision)
    }
}

private final class FrozenFilesSource: ModelFilesService, @unchecked Sendable {
    var url = URL(fileURLWithPath: "/original-model")
    var required = ["weights"]
    func installedTextModelURL(_ id: String) -> URL? { url }
    func installedSpeechModelURL(_ id: String) -> URL? { url }
    func speechRequiredFiles(_ id: String) -> [String] { required }
    func textModelIsComplete(at url: URL) -> Bool { true }
    func installedWhisperURL(_ id: String) -> URL? { url }
    func whisperVariantURL(_ id: String) -> URL { url }
    func whisperModelIsComplete(at url: URL) -> Bool { true }
}
