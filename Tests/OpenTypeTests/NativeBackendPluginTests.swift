import Foundation
import XCTest
import UtterRuntime
import UtterContracts
import UtterMediaContracts
import UtterModels
import UtterMLX
import UtterANE
import UtterWhisper
import UtterRemoteInference

@MainActor
final class NativeBackendPluginTests: XCTestCase {
    func testRegisteredBackendsStayUnloadedAndRevokeRetainedServices() async throws {
        let environment = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.environment", provides: [ModelServices.files.reference, IntegrationServices.diagnostics.reference]
        )) { context, _ in
            try context.provide(ModelServices.files, value: EmptyModelFiles())
            try context.provide(IntegrationServices.diagnostics, value: QuietNativeDiagnostics())
        }
        let registrations = [
            environment, ModelPlugins.resourceAccess(), ModelPlugins.textProviders(), ModelPlugins.imageProviders(), ModelPlugins.speechProviders(),
            MLXPlugins.text(), MLXPlugins.image(), ANEPlugins.text(), WhisperPlugins.speech(),
            MLXPlugins.qwenSpeech(), MLXPlugins.fireredSpeech(), MLXPlugins.megaSpeech(), RemoteInferencePlugins.speech(),
        ]
        let runtime = PluginRuntime(catalog: try PluginCatalog(registrations))
        try await runtime.start(registrations.map { PluginSelection($0.descriptor.id) })
        let providers = try runtime.service(GenerationServices.providers)
        XCTAssertEqual(providers.descriptors.map(\.id), ["generation.ane", "generation.mlx"])
        let mlx = try await providers.create(id: "mlx", request: .inference)
        let ane = try await providers.create(id: "espresso", request: .inference)
        let mlxLoaded = await mlx.isLoaded
        let aneLoaded = await ane.isLoaded
        XCTAssertFalse(mlxLoaded)
        XCTAssertFalse(aneLoaded)
        let speech = try runtime.service(SpeechServices.providers)
        XCTAssertEqual(speech.descriptors.map(\.id), ["speech.firered", "speech.mega", "speech.qwen", "speech.volc", "speech.whisper"])
        let qwen = try await speech.create(id: SpeechEngineType.qwen3.rawValue, request: SpeechProviderRequest(selection: SpeechSelection(providerID: "speech.qwen", type: .qwen3, modelPath: "/missing")))
        XCTAssertFalse(qwen.isReady)
        try await runtime.stop()
        XCTAssertTrue(providers.descriptors.isEmpty)
        for service in [mlx, ane] {
            do {
                _ = try await service.generate(TextGenerationRequest(prompt: "fixture", modelID: "missing"))
                XCTFail("Disposed backend should reject a retained service")
            } catch ModelResourceError.closed { }
        }
    }
}

private struct EmptyModelFiles: ModelFilesService {
    func installedTextModelURL(_ id: String) -> URL? { nil }
    func installedSpeechModelURL(_ id: String) -> URL? { nil }
    func speechRequiredFiles(_ id: String) -> [String] { [] }
    func textModelIsComplete(at url: URL) -> Bool { false }
    func installedWhisperURL(_ id: String) -> URL? { nil }
    func whisperVariantURL(_ id: String) -> URL { URL(fileURLWithPath: "/missing") }
    func whisperModelIsComplete(at url: URL) -> Bool { false }
}

private struct QuietNativeDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
