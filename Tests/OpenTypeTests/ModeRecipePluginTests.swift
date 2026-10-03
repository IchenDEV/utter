import XCTest
import UtterContracts
import UtterMediaContracts
import UtterProcessing
import UtterRuntime

@MainActor
final class ModeRecipePluginTests: XCTestCase {
    func testBuiltinModesUseTheSelectedWorkerAndAReplacementRecipeIsIndependent() async throws {
        var processingCalls = 0
        var seenMode: TextProcessingMode?
        let worker = RecipeProcessingFixture { request in
            processingCalls += 1
            seenMode = request.mode
            return "builtin"
        }
        let processing = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.processing", provides: [ProcessingServices.text.reference])) { context, _ in
            try context.provide(ProcessingServices.text, value: worker)
        }
        let replacement = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.recipe", requires: [ModeServices.recipes.required], provides: [ModeServices.formatting.reference]
        )) { context, _ in
            let descriptor = ProviderDescriptor(id: "mode.replacement", displayName: "Replacement")
            let registry = try context.require(ModeServices.recipes)
            try registry.register(ProviderDefinition(descriptor: descriptor) { _ in RecipeReplacementFixture() }, scope: context.scope)
            try context.provide(ModeServices.formatting, value: descriptor)
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([
            ModePlugins.recipes(), processing, ModePlugins.direct(), replacement
        ]))
        try await runtime.start([PluginSelection("modes.recipes"), PluginSelection("fixture.processing"),
            PluginSelection("mode.direct"), PluginSelection("fixture.recipe")])
        let registry = try runtime.service(ModeServices.recipes)
        let direct = try await registry.create(id: "mode.direct", request: ())
        let formatting = try await registry.create(id: "mode.replacement", request: ())
        let request = ProcessingRequest(mode: .formatting, text: "input", options: TextProcessingOptions(settings: SettingsValues()),
            dictionary: PersonalDictionarySnapshot(entries: [], editRules: []))
        let directResult = try await direct.process(request)
        let replacementResult = try await formatting.process(request)
        XCTAssertEqual(directResult.text, "builtin")
        XCTAssertEqual(replacementResult.text, "replacement")
        XCTAssertEqual(processingCalls, 1)
        XCTAssertEqual(seenMode, .direct)
        try await runtime.stop()
        do { _ = try await direct.process(request); XCTFail("Closed recipe used a worker") } catch {}
    }
}

@MainActor
private final class RecipeReplacementFixture: ModeRecipeService {
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult { ProcessingResult(text: "replacement") }
}

@MainActor
private final class RecipeProcessingFixture: ProcessingService {
    private let result: (ProcessingRequest) -> String
    init(result: @escaping (ProcessingRequest) -> String) { self.result = result }
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult { ProcessingResult(text: result(request)) }
    func resolveEditCommand(text: String, options: TextProcessingOptions, dictionary: PersonalDictionarySnapshot,
        context: SpokenEditCommandResolutionContext) async throws -> SpokenEditCommandLLMResolution? { nil }
}
