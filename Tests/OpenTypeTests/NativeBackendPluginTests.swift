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
    func testSpeechCacheUsesFrozenModelIdentityAcrossPathChanges() async throws {
        let files = WorkflowFiles()
        files.url = URL(fileURLWithPath: "/original-model")
        let environment = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.speech-files", provides: [ModelServices.files.reference, IntegrationServices.diagnostics.reference])) { context, _ in
            try context.provide(ModelServices.files, value: files)
            try context.provide(IntegrationServices.diagnostics, value: QuietNativeDiagnostics())
        }
        let plugins = [environment, ModelPlugins.resourceAccess(), ModelPlugins.speechProviders(), MLXPlugins.qwenSpeech()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        let providers = try runtime.service(SpeechServices.providers)
        let selection = SpeechSelection(providerID: "speech.qwen", type: .qwen3, model: "model", modelPath: "/missing")
        let original = SpeechProviderRequest(selection: selection, modelFiles: FrozenModelFiles(modelID: "model", using: files))
        let first = try await providers.create(id: "speech.qwen", request: original)
        let repeated = try await providers.create(id: "speech.qwen", request: original)
        XCTAssertTrue(first === repeated)
        files.url = URL(fileURLWithPath: "/replacement-model")
        let replacement = try await providers.create(id: "speech.qwen", request: SpeechProviderRequest(selection: selection,
            modelFiles: FrozenModelFiles(modelID: "model", using: files)))
        XCTAssertFalse(first === replacement)
        try await runtime.stop()
    }

    func testRegisteredBackendsStayUnloadedAndRevokeRetainedServices() async throws {
        let environment = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.environment", provides: [ModelServices.files.reference, IntegrationServices.diagnostics.reference]
        )) { context, _ in
            try context.provide(ModelServices.files, value: EmptyModelFiles())
            try context.provide(IntegrationServices.diagnostics, value: QuietNativeDiagnostics())
        }
        let registrations = [
            environment, ModelPlugins.artifacts(), ModelPlugins.resourceAccess(), ModelPlugins.textProviders(), ModelPlugins.imageProviders(), ModelPlugins.speechProviders(),
            MLXPlugins.text(), MLXPlugins.image(), ANEPlugins.text(), WhisperPlugins.speech(),
            MLXPlugins.qwenSpeech(), MLXPlugins.fireredSpeech(), MLXPlugins.megaSpeech(), RemoteInferencePlugins.speech(),
        ]
        let runtime = PluginRuntime(catalog: try PluginCatalog(registrations))
        try await runtime.start(registrations.map { PluginSelection($0.descriptor.id) })
        let artifacts = try runtime.service(ModelServices.artifacts)
        XCTAssertEqual(artifacts.artifacts.filter { $0.kind == .llm }, MLXModelArtifacts.text)
        XCTAssertEqual(artifacts.artifacts.filter { $0.kind == .asr }, MLXModelArtifacts.speech)
        let providers = try runtime.service(GenerationServices.providers)
        XCTAssertEqual(providers.descriptors.map(\.id), ["generation.ane", "generation.mlx"])
        let mlx = try await providers.create(id: "mlx", request: .inference)
        let ane = try await providers.create(id: "espresso", request: .inference)
        for service in [mlx, ane] {
            do {
                try await service.prepare(TextGenerationRequest(prompt: "", modelID: "missing", frozenModel: ModelLocationLease(nil)))
                XCTFail("Frozen absence must reject before backend loading")
            } catch { XCTAssertEqual(error as? GenerationServiceError, .modelUnavailable) }
        }
        let modelRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modelURL = modelRoot.appendingPathComponent("model")
        defer { try? FileManager.default.removeItem(at: modelRoot) }
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        let frozen = ModelLocationLease(modelURL)
        try FileManager.default.moveItem(at: modelURL, to: modelRoot.appendingPathComponent("old"))
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        for service in [mlx, ane] {
            do {
                try await service.prepare(TextGenerationRequest(prompt: "", modelID: "replacement", frozenModel: frozen))
                XCTFail("A frozen request loaded a later published model")
            } catch { XCTAssertEqual(error as? GenerationServiceError, .modelChanged) }
        }
        let mlxLoaded = await mlx.isLoaded
        let aneLoaded = await ane.isLoaded
        XCTAssertFalse(mlxLoaded)
        XCTAssertFalse(aneLoaded)
        await mlx.unload()
        let imageProviders = try runtime.service(ImageGenerationServices.providers)
        let image = try await imageProviders.create(id: "generation.mlx-image", request: .inference)
        await image.unload()
        let speech = try runtime.service(SpeechServices.providers)
        XCTAssertEqual(speech.descriptors.map(\.id), ["speech.firered", "speech.mega", "speech.qwen", "speech.volc", "speech.whisper"])
        let qwen = try await speech.create(id: SpeechEngineType.qwen3.rawValue, request: SpeechProviderRequest(selection: SpeechSelection(providerID: "speech.qwen", type: .qwen3, modelPath: "/missing")))
        XCTAssertFalse(qwen.isReady)
        let whisperRequest = SpeechProviderRequest(selection: SpeechSelection(
            providerID: "speech.whisper", type: .whisper, model: "tiny"))
        let whisper = try await speech.create(id: "speech.whisper", request: whisperRequest)
        XCTAssertFalse(whisper.isReady, "The factory must return before cold model preparation")
        let repeatedWhisper = try await speech.create(id: "speech.whisper", request: whisperRequest)
        XCTAssertTrue(whisper === repeatedWhisper)
        try await runtime.stop()
        XCTAssertTrue(providers.descriptors.isEmpty)
        XCTAssertTrue(artifacts.artifacts.isEmpty)
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
