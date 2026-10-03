import Foundation
import XCTest
import UtterContracts
import UtterModels
import UtterRuntime

@MainActor
final class ModelFilesPluginTests: XCTestCase {
    func testMountingFileMetadataDoesNotCreateDirectoriesAndDisposesObservation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = FileFixtureSettings(root: root)
        let runtime = try await mount(settings)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(settings.observers.count, 1)
        let files = try runtime.service(ModelServices.files)
        XCTAssertEqual(files.speechRequiredFiles("custom"), ["custom.weights"])
        try await runtime.stop()
        XCTAssertTrue(settings.observers.isEmpty)
        settings.update { $0.modelStoragePath = "/later-root" }
        XCTAssertEqual(files.whisperVariantURL("variant").path, root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/variant").path)
    }

    func testNextLookupUsesNewStorageRootWhileFrozenGenerationKeepsItsModelURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        for root in [first, second] {
            let model = ConfiguredModelFiles.repositoryDirectory("model", storageRoot: root)
            try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
            for name in ["config.json", "model.safetensors"] {
                try Data("valid".utf8).write(to: model.appendingPathComponent(name))
            }
        }
        let settings = FileFixtureSettings(root: first)
        let runtime = try await mount(settings)
        let files = try runtime.service(ModelServices.files)
        let request = TextGenerationRequest(prompt: "frozen", modelID: "model", modelURL: files.installedTextModelURL("model"))
        settings.update { $0.modelStoragePath = second.path }
        XCTAssertEqual(files.installedTextModelURL("model")?.path, ConfiguredModelFiles.repositoryDirectory("model", storageRoot: second).path)
        XCTAssertEqual(request.modelURL?.path, ConfiguredModelFiles.repositoryDirectory("model", storageRoot: first).path)
        try await runtime.stop()
        XCTAssertTrue(settings.observers.isEmpty)
    }

    private func mount(_ settings: FileFixtureSettings) async throws -> PluginRuntime {
        let source = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.settings", provides: [DataServices.settings.reference]
        )) { context, _ in try context.provide(DataServices.settings, value: settings) }
        let plugins = [source, ModelPlugins.files(speechRequirements: ["custom": ["custom.weights"]])]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        return runtime
    }
}

private final class FileFixtureSettings: SettingsService {
    private(set) var values = SettingsValues()
    private(set) var observers: [UUID: (SettingsValues) -> Void] = [:]
    init(root: URL) { values.modelStoragePath = root.path }
    func update(_ mutation: (inout SettingsValues) -> Void) {
        mutation(&values)
        for callback in Array(observers.values) { callback(values) }
    }
    func observe(_ callback: @escaping (SettingsValues) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }
    func removeObserver(_ id: UUID) { observers[id] = nil }
    func resetDeveloperHTTPToken() {}
}
