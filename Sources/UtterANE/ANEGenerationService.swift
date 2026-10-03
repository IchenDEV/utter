import Foundation
import UtterContracts

package struct ANEGenerationService: TextGenerationService {
    private let engine: EspressoLLMEngine
    private let access: any ModelResourceAccess
    private let files: any ModelFilesService
    private let log: Log

    package init(files: any ModelFilesService, access: any ModelResourceAccess, log: Log) {
        engine = EspressoLLMEngine(files: files, log: log)
        self.access = access
        self.files = files
        self.log = log
    }

    package func generate(_ request: TextGenerationRequest) async throws -> String {
        try await access.withAccess {
            try await engine.loadModel(path: request.modelURL?.path ?? request.modelID)
            try Task.checkCancellation()
            return try await engine.generate(
                prompt: request.prompt, systemPrompt: request.systemPrompt ?? "",
                maxTokens: request.maxTokens, temperature: request.temperature
            )
        }
    }

    package func prepare(_ request: TextGenerationRequest) async throws {
        try await access.withAccess { try await engine.loadModel(path: request.modelURL?.path ?? request.modelID) }
    }

    package var isLoaded: Bool { get async { await engine.isLoaded } }
    package func unload() async { try? await access.withAccess { await engine.unload() } }
    package func validateModel(at url: URL) async throws {
        try await access.withAccess { try await EspressoLLMEngine.validateModelDirectory(at: url, files: files, log: log) }
    }
    package func close() async {
        try? await access.withAccess {
            await engine.close()
        }
    }

}
