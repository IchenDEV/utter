import CoreGraphics
import Foundation
import UtterContracts
import UtterMediaContracts

extension TextProcessor {
    func generationRequest(
        prompt: String, systemPrompt: String?, options: TextProcessingOptions,
        maxTokens: Int, temperature: Double, usesANE: Bool = false
    ) -> TextGenerationRequest {
        let modelID = options.useRemoteLLM ? options.remoteModel : options.llmModel
        let modelURL = usesANE
            ? URL(fileURLWithPath: NSString(string: options.espressoModelPath).expandingTildeInPath)
            : modelFiles.installedTextModelURL(modelID)
        let remote = options.useRemoteLLM
            ? RemoteGenerationConfiguration(baseURL: options.remoteBaseURL, apiKey: options.remoteAPIKey, provider: options.remoteProvider)
            : nil
        return TextGenerationRequest(
            prompt: prompt, systemPrompt: systemPrompt, modelID: modelID, modelURL: modelURL,
            maxTokens: maxTokens, temperature: temperature, remote: remote
        )
    }

    func generateText(
        prompt: String, systemPrompt: String, options: TextProcessingOptions, maxTokens: Int, temperature: Double
    ) async throws -> String {
        let providerID = options.textProviderID ?? (options.useRemoteLLM ? "remote" : options.localLLMBackend.rawValue)
        let usesANE = !options.useRemoteLLM && options.localLLMBackend == .espresso
        let request = generationRequest(
            prompt: prompt, systemPrompt: systemPrompt, options: options,
            maxTokens: maxTokens, temperature: temperature, usesANE: usesANE
        )
        let fallbackRequest = generationRequest(
            prompt: prompt, systemPrompt: systemPrompt, options: options,
            maxTokens: maxTokens, temperature: temperature
        )
        let primary = try await providers.create(id: providerID, request: .inference)
        try Task.checkCancellation()
        guard usesANE else {
            await Self.clearEspressoOutcome()
            let result = try await primary.generate(request)
            try Task.checkCancellation()
            return result
        }
        return try await withLocalModelAccess {
            do {
                let result = try await Self.runEspressoWithMLXFallback(
                    fallbackEnabled: options.fallbackToMLXOnEspressoFailure,
                    espresso: { try await primary.generate(request) },
                    prepareForMLXFallback: { await primary.unload() },
                    mlx: {
                        let fallback = try await self.providers.create(id: options.fallbackProviderID, request: .inference)
                        try Task.checkCancellation()
                        return try await fallback.generate(fallbackRequest)
                    }
                )
                if result.usedMLX {
                    await Self.recordEspressoOutcome(.fallback)
                    Log.info("[TextProcessor] ANE-LM failed; unloaded it and used the selected MLX model")
                } else {
                    await Self.clearEspressoOutcome()
                }
                return result.value
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as EspressoMLXFallbackError {
                await Self.recordEspressoOutcome(.unavailable)
                Log.sensitive("[TextProcessor] ANE-LM and MLX fallback failed: \(error.details)")
                throw error
            } catch {
                if !options.fallbackToMLXOnEspressoFailure { await Self.recordEspressoOutcome(.failed) }
                throw error
            }
        }
    }

    static func runEspressoWithMLXFallback<Value>(
        fallbackEnabled: Bool = true,
        espresso: () async throws -> Value,
        prepareForMLXFallback: () async -> Void = {},
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
            await prepareForMLXFallback()
            try Task.checkCancellation()
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
        prompt: String, systemPrompt: String, model: String, image: CGImage,
        maxTokens: Int, temperature: Double, providerID: String = "generation.mlx-image"
    ) async throws -> String {
        let request = TextGenerationRequest(
            prompt: prompt, systemPrompt: systemPrompt, modelID: model, modelURL: modelFiles.installedTextModelURL(model),
            maxTokens: maxTokens, temperature: temperature
        )
        let provider = try await imageProviders.create(id: providerID, request: .inference)
        try Task.checkCancellation()
        let result = try await provider.generate(ImageGenerationRequest(text: request, image: image))
        try Task.checkCancellation()
        return result
    }

    func shouldUseScreenImage(options: TextProcessingOptions, image: CGImage?) -> Bool {
        guard image != nil, options.screenContextMode == .multimodal,
              !options.useRemoteLLM, options.localLLMBackend == .mlx else { return false }
        return ScreenContextMode.supportsScreenImageContext(modelID: options.llmModel)
    }
}
