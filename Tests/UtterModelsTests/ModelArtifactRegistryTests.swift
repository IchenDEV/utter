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
        let runtime = PluginRuntime(catalog: try PluginCatalog([registry, provider]))
        try await runtime.start([PluginSelection("models.artifacts"), PluginSelection("replacement.speech")])
        let artifacts = try runtime.service(ModelServices.artifacts)
        XCTAssertEqual(artifacts.artifacts.map(\.id), ["vendor/replacement"])
        XCTAssertEqual(artifacts.artifact("vendor/replacement")?.requiredFiles, ["weights.bin", "vocabulary.txt"])
        try await runtime.stop()
        XCTAssertTrue(artifacts.artifacts.isEmpty)
    }
}
