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
            await Self.clearEspressoOutcome()
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

        return try await withLocalModelAccess {
            try Task.checkCancellation()
            switch options.localLLMBackend {
            case .mlx:
                await Self.clearEspressoOutcome()
                await ensureModelLoaded(options.llmModel)
                return try await llm.generate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens,
                    temperature: temperature
                )
            case .espresso:
                do {
                    let result = try await Self.runEspressoWithMLXFallback(
                        fallbackEnabled: options.fallbackToMLXOnEspressoFailure,
                        espresso: {
                            try await self.espressoLLM.loadModel(path: options.espressoModelPath)
                            return try await self.espressoLLM.generate(
                                prompt: prompt,
                                systemPrompt: systemPrompt,
                                maxTokens: maxTokens,
                                temperature: temperature
                            )
                        },
                        mlx: {
                            try await self.llm.loadModel(id: options.llmModel)
                            return try await self.llm.generate(
                                prompt: prompt,
                                systemPrompt: systemPrompt,
                                maxTokens: maxTokens,
                                temperature: temperature
                            )
                        }
                    )
                    if result.usedMLX {
                        _ = await espressoLLM.consumeLastFailureMessage()
                        await Self.recordEspressoOutcome(.fallback)
                        Log.info("[TextProcessor] ANE-LM failed; used the selected MLX model")
                    } else {
                        await Self.clearEspressoOutcome()
                    }
                    return result.value
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as EspressoMLXFallbackError {
                    _ = await espressoLLM.consumeLastFailureMessage()
                    await Self.recordEspressoOutcome(.unavailable)
                    Log.sensitive("[TextProcessor] ANE-LM and MLX fallback failed: \(error.details)")
                    Log.error("[TextProcessor] MLX fallback unavailable")
                    throw error
                } catch {
                    if !options.fallbackToMLXOnEspressoFailure {
                        _ = await espressoLLM.consumeLastFailureMessage()
                        await Self.recordEspressoOutcome(.failed)
                        Log.error("[TextProcessor] ANE-LM failed; MLX fallback is disabled")
                    }
                    throw error
                }
            }
        }
    }

    static func runEspressoWithMLXFallback<Value>(
        fallbackEnabled: Bool = true,
        espresso: () async throws -> Value,
        mlx: () async throws -> Value
    ) async throws -> (value: Value, usedMLX: Bool) {
        do {
            let value = try await espresso()
            try Task.checkCancellation()
            return (value, false)
        } catch {
            try Task.checkCancellation()
            guard fallbackEnabled else { throw error }
            let espressoFailure = error.localizedDescription
            do {
                let value = try await mlx()
                try Task.checkCancellation()
                return (value, true)
            } catch {
                try Task.checkCancellation()
                throw EspressoMLXFallbackError(
                    espressoFailure: espressoFailure,
                    mlxFailure: error.localizedDescription
                )
            }
        }
    }

    struct EspressoMLXFallbackError: LocalizedError {
        let espressoFailure: String
        let mlxFailure: String

        var errorDescription: String? {
            L("error.espresso_mlx_fallback_unavailable")
        }

        var details: String {
            "ANE-LM: \(espressoFailure); MLX: \(mlxFailure)"
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
        try await withLocalModelAccess {
            try Task.checkCancellation()
            await Self.clearEspressoOutcome()
            try await vlm.loadModel(id: model)
            return try await vlm.generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                image: image,
                maxTokens: maxTokens,
                temperature: temperature
            )
        }
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
