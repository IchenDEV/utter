import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
final class ScopedProcessingModels: ProcessingModelService {
    private let processor: TextProcessor
    private let scope: PluginScope
    init(processor: TextProcessor, scope: PluginScope) { self.processor = processor; self.scope = scope }
    func prepare(_ options: TextProcessingOptions) async throws -> EspressoGenerationOutcome? {
        try await scope.run { try await self.processor.prepareModel(options) }
    }
    func unload() async throws {
        try await scope.run { try await self.processor.resetModels() }
    }

    func benchmark(_ modelID: String) async throws -> ModelBenchmarkResult {
        try await scope.run { try await self.processor.benchmarkLLM(modelID: modelID) }
    }
}
