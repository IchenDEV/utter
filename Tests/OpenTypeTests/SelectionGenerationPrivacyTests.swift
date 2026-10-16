import Foundation
import Synchronization
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterModels
import UtterProcessing
import UtterRuntime

@MainActor
final class SelectionGenerationPrivacyTests: XCTestCase {
    func testSelectedBackendAndFallbackFailureLogNoPromptOrErrorPayload() async {
        let diagnostics = SelectionPrivacyDiagnostics()
        let providers = SelectionPrivacyProviders()
        var settings = SettingsValues()
        settings.localLLMBackend = .espresso
        let dictionary = PersonalDictionarySnapshot(entries: [], editRules: [])
        let processor = TextProcessor(providers: providers, imageProviders: nil, access: LocalModelAccessGate(),
            files: WorkflowFiles(), settings: { settings }, dictionary: { dictionary }, log: Log(service: diagnostics))
        var options = TextProcessingOptions(settings: settings)
        options.textProviderID = "generation.ane"
        options.fallbackProviderID = "generation.mlx"
        let candidate = await processor.processSelectionEdit(selectedText: "synthetic private original 👩🏽‍💻",
            intent: .custom("rewrite politely"), options: options, dictionarySnapshot: dictionary)
        XCTAssertEqual(candidate, "")
        XCTAssertEqual(providers.created, ["generation.ane", "generation.mlx"])
        XCTAssertEqual(diagnostics.messages, ["[TextProcessor] Selection edit failed"])
    }
}

@MainActor
private final class SelectionPrivacyProviders: ProviderCatalog {
    typealias Request = GenerationPurpose
    typealias Value = any TextGenerationService
    let descriptors = [ProviderDescriptor(id: "generation.ane", displayName: "Test", modelLocation: .bundle),
        ProviderDescriptor(id: "generation.mlx", displayName: "Test")]
    var created: [String] = []
    func register(_ definition: ProviderDefinition<GenerationPurpose, any TextGenerationService>, scope: PluginScope) throws {
        throw ProviderCatalogError.closed
    }
    func create(id: String, request: GenerationPurpose) async throws -> any TextGenerationService {
        created.append(id)
        return SelectionPrivacyFailure()
    }
}

private struct SelectionPrivacyFailure: TextGenerationService {
    func generate(_ request: TextGenerationRequest) async throws -> String {
        throw NSError(domain: "SyntheticSelectedBackend", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synthetic private candidate 🇸🇬 echoed in provider failure"])
    }
}

private final class SelectionPrivacyDiagnostics: DiagnosticsService {
    private let recorded = Mutex<[String]>([])
    var messages: [String] { recorded.withLock { $0 } }
    func info(_ message: String) { recorded.withLock { $0.append(message) } }
    func sensitive(_ message: String) { recorded.withLock { $0.append(message) } }
    func error(_ message: String) { recorded.withLock { $0.append(message) } }
}
