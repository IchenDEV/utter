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
        try await scope.run {
            try await self.processor.withLocalModelAccess {
                for descriptor in await self.processor.providers.descriptors {
                    try await self.processor.providers.reset(id: descriptor.id)
                }
                if let images = self.processor.imageProviders {
                    for descriptor in await images.descriptors { try await images.reset(id: descriptor.id) }
                }
            }
        }
    }
    func benchmark(_ modelID: String) async throws -> ModelBenchmarkResult {
        try await scope.run { try await self.processor.benchmarkLLM(modelID: modelID) }
    }
}
