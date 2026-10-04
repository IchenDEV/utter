import Foundation
import XCTest
import UtterContracts
import UtterRuntime
@testable import UtterModels

final class ModelArtifactRegistryTests: XCTestCase {
    @MainActor
    func testBackendReplacementChangesItsModelListAndFileContract() async throws {
        let registry = ModelPlugins.artifacts()
        let provider = PluginRegistration(descriptor: PluginDescriptor(
            id: "replacement.speech", requires: [ModelServices.artifacts.required]
        )) { context, _ in
            let artifacts = try context.require(ModelServices.artifacts)
            try artifacts.register(ModelArtifact(id: "vendor/replacement", kind: .asr,
                displayName: "Replacement", requiredFiles: ["weights.bin", "vocabulary.txt"]), scope: context.scope)
        }
        let settings = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.settings", provides: [DataServices.settings.reference])) { context, _ in
            try context.provide(DataServices.settings, value: FileFixtureSettings(root: URL(fileURLWithPath: "/missing")))
        }
        let plugins = [settings, registry, provider, ModelPlugins.files()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        let artifacts = try runtime.service(ModelServices.artifacts)
        let files = try runtime.service(ModelServices.files)
        XCTAssertEqual(files.speechRequiredFiles("vendor/replacement"), ["weights.bin", "vocabulary.txt"])
        XCTAssertEqual(files.speechRequiredFiles("unknown"), [])
        XCTAssertEqual(artifacts.artifacts.map(\.id), ["vendor/replacement"])
        XCTAssertEqual(artifacts.artifact("vendor/replacement")?.requiredFiles, ["weights.bin", "vocabulary.txt"])
        try await runtime.stop()
        XCTAssertTrue(artifacts.artifacts.isEmpty)
    }
}
