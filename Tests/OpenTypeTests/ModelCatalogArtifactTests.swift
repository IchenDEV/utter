import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterModels
import UtterRuntime

@MainActor
final class ModelCatalogArtifactTests: XCTestCase {
    func testProductionCatalogUsesRegisteredArtifactsAndTheirValidationContract() async throws {
        let suite = "ModelArtifacts-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(root.path, forKey: "modelStoragePath")
        let speechModel = ModelArtifact(id: "vendor/recognizer", kind: .asr, displayName: "Recognizer", requiredFiles: ["weights.bin", "vocabulary.txt"])
        let textModel = ModelArtifact(id: "vendor/formatter", kind: .llm, displayName: "Formatter", family: .qwen, tier: .recommended)
        let backend = PluginRegistration(descriptor: PluginDescriptor(id: "replacement.backend", requires: [ModelServices.artifacts.required, SpeechServices.providers.required])) { context, _ in
            try context.require(ModelServices.artifacts).register([speechModel, textModel], scope: context.scope)
            let descriptor = ProviderDescriptor(id: "replacement.speech", legacyIDs: [SpeechEngineType.qwen3.rawValue], displayName: "Recognizer", artifacts: [speechModel])
            try context.require(SpeechServices.providers).register(ProviderDefinition(descriptor: descriptor) { _ in WorkflowSpeech() }, scope: context.scope)
        }
        let downloads = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.downloads", provides: [ModelServices.textDownloads.reference])) { context, _ in
            try context.provide(ModelServices.textDownloads, value: ArtifactTestDownloads())
        }
        let plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.diagnostics(ArtifactTestLog()),
                       ModelPlugins.resourceAccess(), ModelPlugins.artifacts(), ModelPlugins.files(), ModelPlugins.speechProviders(),
                       backend, downloads, ModelPlugins.catalog()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        let catalog = try runtime.service(ModelServices.catalog)
        let files = try runtime.service(ModelServices.files)
        XCTAssertEqual(catalog.snapshot.text.map(\.id), [textModel.id])
        XCTAssertEqual(catalog.snapshot.speech.map(\.id), [speechModel.id])
        XCTAssertEqual(catalog.snapshot.text.first?.tier, .standard, "Unknown memory requirements cannot advertise a recommendation")
        XCTAssertEqual(files.speechRequiredFiles(speechModel.id), speechModel.requiredFiles)
        let directory = root.appendingPathComponent("models").appendingPathComponent(speechModel.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: directory.appendingPathComponent("weights.bin"))
        catalog.refreshStatus(recheckingErrors: true)
        XCTAssertNotEqual(catalog.snapshot.speech.first?.status, .downloaded)
        try Data("vocabulary".utf8).write(to: directory.appendingPathComponent("vocabulary.txt"))
        catalog.refreshStatus(recheckingErrors: true)
        XCTAssertEqual(catalog.snapshot.speech.first?.status, .downloaded)
        try await runtime.stop()
        XCTAssertThrowsError(try runtime.service(ModelServices.catalog))
    }

}

private struct ArtifactTestDownloads: TextModelDownloadService {
    func download(_ id: String, downloadBase: URL, cacheDirectory: URL, progress: @escaping @Sendable (Progress) -> Void) async throws {}
    func validate(_ directory: URL) async throws {}
}
private struct ArtifactTestLog: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
