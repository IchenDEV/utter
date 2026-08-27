import CoreGraphics
import Foundation

extension TextProcessor {
    func generateText(
        prompt: String,
        systemPrompt: String,
        options: TextProcessingOptions,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        if options.useRemoteLLM {
            return try await remoteLLMClient.generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                baseURL: options.remoteBaseURL,
                apiKey: options.remoteAPIKey,
                model: options.remoteModel,
                provider: options.remoteProvider,
                maxTokens: maxTokens,
                temperature: temperature
            )
        }

        switch options.localLLMBackend {
        case .mlx:
            await ensureModelLoaded(options.llmModel)
            return try await llm.generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        case .espresso:
            try await espressoLLM.loadModel(path: options.espressoModelPath)
            return try await espressoLLM.generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        }
    }

    func generateWithScreenImage(
        prompt: String,
        systemPrompt: String,
        model: String,
        image: CGImage,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        try await vlm.loadModel(id: model)
        return try await vlm.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            image: image,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    func shouldUseScreenImage(options: TextProcessingOptions, image: CGImage?) -> Bool {
        guard image != nil else { return false }
        guard options.screenContextMode == .multimodal,
              !options.useRemoteLLM,
              options.localLLMBackend == .mlx else { return false }
        return ScreenContextMode.supportsScreenImageContext(modelID: options.llmModel)
    }

    private func ensureModelLoaded(_ model: String) async {
        guard !(await llm.isLoaded) else { return }
        do {
            try await llm.loadModel(id: model)
        } catch {
            Log.error("[TextProcessor] on-demand model load failed: \(error.localizedDescription)")
        }
    }

}
