import Foundation
import UtterContracts

package struct MLXGenerationService: TextGenerationService {
    private let engine: LLMEngine
    private let access: any ModelResourceAccess

    package init(files: any ModelFilesService, access: any ModelResourceAccess, log: Log) {
        engine = LLMEngine(files: files, log: log)
        self.access = access
    }

    package func generate(_ request: TextGenerationRequest) async throws -> String {
        try await access.withAccess {
            try Task.checkCancellation()
            try await engine.loadModel(id: request.modelID, modelURL: request.modelURL)
            try Task.checkCancellation()
            let result = try await engine.generate(
                prompt: request.prompt, systemPrompt: request.systemPrompt,
                maxTokens: request.maxTokens, temperature: request.temperature
            )
            try Task.checkCancellation()
            return result
        }
    }

    package func prepare(_ request: TextGenerationRequest) async throws {
        try await access.withAccess { try await engine.loadModel(id: request.modelID, modelURL: request.modelURL) }
    }

    package var isLoaded: Bool { get async { await engine.isLoaded } }

    package func unload() async {
        try? await access.withAccess {
            await engine.unload()
        }
    }

    package func benchmark(_ request: TextGenerationRequest) async throws -> ModelBenchmarkResult {
        try await access.withAccess {
            do {
                let result = try await engine.benchmark(modelID: request.modelID, modelURL: request.modelURL)
                await engine.unload()
                return result
            } catch {
                await engine.unload()
                throw error
            }
        }
    }
    package func close() async {
        try? await access.withAccess {
            await engine.close()
        }
    }

}
