import Foundation
import XCTest
import UtterContracts
import UtterRuntime
import UtterRemoteInference

@MainActor
final class RemoteConnectionPluginTests: XCTestCase {
    func testConnectionUsesTheRegisteredReplacementAndRevokesRetainedActions() async throws {
        let model = ConnectionModel()
        let environment = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.remote", provides: [
            GenerationServices.providers.reference, GenerationServices.remote.reference
        ])) { context, _ in
            let providers = ProviderRegistry<GenerationPurpose, any TextGenerationService>()
            let descriptor = ProviderDescriptor(id: "generation.replacement", displayName: "Replacement", modelLocation: .remote)
            try providers.register(ProviderDefinition(descriptor: descriptor) { _ in model }, scope: context.scope)
            try context.provide(GenerationServices.providers, value: providers)
            try context.provide(GenerationServices.remote, value: descriptor)
        }
        let plugins = [environment, RemoteInferencePlugins.connection()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        let connection = try runtime.service(GenerationServices.connection)
        try await connection.test(configuration: RemoteGenerationConfiguration(baseURL: "https://fixture.invalid",
            apiKey: "fixture", provider: .openai), modelID: "replacement-model")
        let requests = await model.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.modelID, "replacement-model")
        XCTAssertEqual(requests.first?.maxTokens, 10)
        XCTAssertEqual(requests.first?.remote?.baseURL, "https://fixture.invalid")
        try await runtime.stop()
        do {
            try await connection.test(configuration: RemoteGenerationConfiguration(baseURL: "https://fixture.invalid",
                apiKey: "fixture", provider: .openai), modelID: "replacement-model")
            XCTFail("Retired UI actions must not contact a provider")
        } catch {}
        let finalCount = await model.requests.count
        XCTAssertEqual(finalCount, 1)
    }
}

private actor ConnectionModel: TextGenerationService {
    var requests: [TextGenerationRequest] = []
    func generate(_ request: TextGenerationRequest) async throws -> String { requests.append(request); return "Hi" }
}
