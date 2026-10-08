import Foundation
import XCTest
import UtterContracts
import UtterModels

final class ModelFilesTests: XCTestCase {
    func testCompleteConfiguredLocalModelOverridesDownloadedRepository() throws {
        try withDirectory { root in
            var values = SettingsValues()
            values.modelStoragePath = root.path
            values.localLLMModelPaths["model"] = root.appendingPathComponent("local").path
            let files = self.files(values)
            let downloaded = ConfiguredModelFiles.repositoryDirectory("model", storageRoot: root)
            try self.writeModel(at: downloaded)
            XCTAssertNil(files.installedTextModelURL("model"))
            let local = root.appendingPathComponent("local")
            try self.writeModel(at: local)
            XCTAssertEqual(files.installedTextModelURL("model")?.path, local.path)
        }
    }

    func testRepositoryAndWhisperPathsPreservePublishedLayout() throws {
        try withDirectory { root in
            var values = SettingsValues()
            values.modelStoragePath = root.path
            let files = self.files(values)
            XCTAssertEqual(files.whisperVariantURL("variant").path, root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/variant").path)
            XCTAssertNil(files.installedSpeechModelURL("org/model"))
            let directory = root.appendingPathComponent("models/org/model")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            XCTAssertEqual(files.installedSpeechModelURL("org/model")?.path, directory.path)
        }
    }

    func testInjectedSpeechRequirementsReplaceLegacyAssumptions() {
        let files = ConfiguredModelFiles(settings: { SettingsValues() }, speechRequiredFiles: { ["\($0).custom"] })
        XCTAssertEqual(files.speechRequiredFiles("replacement-provider"), ["replacement-provider.custom"])
    }

    func testLocalWhisperPathRemainsAvailableForMissingModelDiagnostics() {
        var values = SettingsValues()
        values.localWhisperModelPaths["local/model"] = "/missing-user-model"
        let files = self.files(values)
        XCTAssertEqual(files.installedWhisperURL("local/model")?.path, "/missing-user-model")
        XCTAssertFalse(files.whisperModelIsComplete(at: URL(fileURLWithPath: "/missing-user-model")))
    }

    private func files(_ values: SettingsValues) -> ConfiguredModelFiles {
        ConfiguredModelFiles(settings: { values }, speechRequiredFiles: { _ in ["config.json"] })
    }
    private func withDirectory(_ operation: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try operation(root)
    }
    private func writeModel(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in ["config.json", "model.safetensors"] { try Data("valid".utf8).write(to: url.appendingPathComponent(name)) }
    }
}
