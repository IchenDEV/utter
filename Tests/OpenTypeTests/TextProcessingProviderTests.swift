import UtterProcessing
import Foundation
import Synchronization
import XCTest
import UtterRuntime
import UtterContracts
import UtterMediaContracts
import UtterModels
@testable import OpenType

@MainActor
final class TextProcessingProviderTests: XCTestCase {
    func testExplicitProviderKeepsModelLocationBeforeFactorySuspends() async throws {
        let files = MutableModelFiles()
        let backend = CapturingTextBackend()
        let (runtime, processor) = try await fixture(files: files, backend: backend)
        var options = TextProcessingOptions(settings: SettingsValues())
        options.textProviderID = "fixture.text"
        options.llmModel = "selected-model"
        let result = try await processor.generateText(prompt: "input", systemPrompt: "system", options: options, maxTokens: 512, temperature: 0.1)
        XCTAssertEqual(result, "generated")
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.modelID, "selected-model")
        XCTAssertEqual(requests.first?.modelURL?.path, "/original-model")
        XCTAssertEqual(files.installedTextModelURL("selected-model")?.path, "/new-model")
        try await runtime.stop()
    }

    func testCancelledProviderCannotPublishLateResultOrStartFallback() async throws {
        let files = MutableModelFiles()
        let backend = CapturingTextBackend(cancels: true)
        let (runtime, processor) = try await fixture(files: files, backend: backend)
        var options = TextProcessingOptions(settings: SettingsValues())
        options.textProviderID = "fixture.text"
        options.localLLMBackend = .espresso
        options.fallbackToMLXOnEspressoFailure = true
        options.fallbackProviderID = "missing-fallback"
        let task = Task {
            try await processor.generateText(prompt: "input", systemPrompt: "system", options: options, maxTokens: 512, temperature: 0.1)
        }
        do { _ = try await task.value; XCTFail("Cancelled result must be rejected") }
        catch is CancellationError { }
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 1)
        try await runtime.stop()
    }

    private func fixture(files: MutableModelFiles, backend: CapturingTextBackend) async throws -> (PluginRuntime, TextProcessor) {
        let marker = ServiceKey<Bool>("fixture.registered")
        let registration = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.backends", requires: [GenerationServices.providers.required], provides: [marker.reference]
        )) { context, _ in
            let providers = try context.require(GenerationServices.providers)
            try providers.register(ProviderDefinition(descriptor: ProviderDescriptor(id: "fixture.text", displayName: "Fixture")) { _ in
                files.changeLocation()
                return backend
            }, scope: context.scope)
            try context.provide(marker, value: true)
        }
        let registrations = [ModelPlugins.resourceAccess(), ModelPlugins.textProviders(), ModelPlugins.imageProviders(), registration]
        let runtime = PluginRuntime(catalog: try PluginCatalog(registrations))
        try await runtime.start(registrations.map { PluginSelection($0.descriptor.id) })
        let processor = TextProcessor(
            providers: try runtime.service(GenerationServices.providers),
            imageProviders: try runtime.service(ImageGenerationServices.providers),
            access: try runtime.service(ModelServices.resourceAccess), files: files
        )
        return (runtime, processor)
    }
}

private actor CapturingTextBackend: TextGenerationService {
    private let cancels: Bool
    private(set) var requests: [TextGenerationRequest] = []
    init(cancels: Bool = false) { self.cancels = cancels }

    func generate(_ request: TextGenerationRequest) async throws -> String {
        requests.append(request)
        if cancels { withUnsafeCurrentTask { $0?.cancel() } }
        return "generated"
    }
}

private final class MutableModelFiles: ModelFilesService {
    private let location = Mutex(URL(fileURLWithPath: "/original-model"))
    func changeLocation() { location.withLock { $0 = URL(fileURLWithPath: "/new-model") } }
    func installedTextModelURL(_ id: String) -> URL? { location.withLock { $0 } }
    func installedSpeechModelURL(_ id: String) -> URL? { nil }
    func speechRequiredFiles(_ id: String) -> [String] { [] }
    func textModelIsComplete(at url: URL) -> Bool { false }
    func installedWhisperURL(_ id: String) -> URL? { nil }
    func whisperVariantURL(_ id: String) -> URL { URL(fileURLWithPath: "/missing") }
    func whisperModelIsComplete(at url: URL) -> Bool { false }
}
