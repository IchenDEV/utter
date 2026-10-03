import UtterContracts
import UtterMediaContracts

package struct MLXImageGenerationService: ImageGenerationService {
    private let engine: VLMEngine
    private let access: any ModelResourceAccess

    package init(files: any ModelFilesService, access: any ModelResourceAccess, log: Log) {
        engine = VLMEngine(files: files, log: log)
        self.access = access
    }

    package func generate(_ request: ImageGenerationRequest) async throws -> String {
        try await access.withAccess {
            try await engine.loadModel(id: request.text.modelID, modelURL: request.text.modelURL)
            try Task.checkCancellation()
            let result = try await engine.generate(
                prompt: request.text.prompt, systemPrompt: request.text.systemPrompt,
                image: request.image, maxTokens: request.text.maxTokens, temperature: request.text.temperature
            )
            try Task.checkCancellation()
            return result
        }
    }

    package func unload() async {
        try? await access.withAccess {
            await engine.unload()
        }
    }
    package func close() async {
        try? await access.withAccess {
            await engine.close()
        }
    }

}
