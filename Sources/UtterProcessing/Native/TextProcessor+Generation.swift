import CoreGraphics
import Foundation
import UtterContracts
import UtterMediaContracts

extension TextProcessor {
    @MainActor
    package func effectiveProviderOptions(_ options: TextProcessingOptions) -> TextProcessingOptions {
        guard let id = options.textProviderID,
              let descriptor = providers.descriptors.first(where: { $0.id == id || $0.legacyIDs.contains(id) }) else { return options }
        return options.selecting(descriptor)
    }

    package func generationRequest(
        prompt: String, systemPrompt: String?, options: TextProcessingOptions,
        maxTokens: Int, temperature: Double, usesANE: Bool = false
    ) -> TextGenerationRequest {
        let modelID = options.useRemoteLLM ? options.remoteModel : options.llmModel
        let modelURL: URL?
        switch options.modelLocations {
        case .unresolved:
            modelURL = usesANE
                ? URL(fileURLWithPath: NSString(string: options.espressoModelPath).expandingTildeInPath)
                : modelFiles.installedTextModelURL(modelID)
        case .frozen(let bundle, let directory):
            modelURL = options.useRemoteLLM ? nil : (usesANE ? bundle : directory)
        }
        let remote = options.useRemoteLLM
            ? RemoteGenerationConfiguration(baseURL: options.remoteBaseURL, apiKey: options.remoteAPIKey, provider: options.remoteProvider)
            : nil
        let frozenModel: ModelLocationLease?
        switch options.modelLocations {
        case .unresolved: frozenModel = nil
        case .frozen:
            frozenModel = options.useRemoteLLM ? nil
                : (usesANE ? options.modelVersions?.bundle : options.modelVersions?.directory) ?? ModelLocationLease(modelURL)
        }
        return TextGenerationRequest(
            prompt: prompt, systemPrompt: systemPrompt, modelID: modelID, modelURL: modelURL,
            maxTokens: min(maxTokens, max(1, options.generationTokenLimit ?? maxTokens)),
            temperature: temperature, remote: remote,
            frozenModel: frozenModel
        )
    }

    package func generateText(
        prompt: String, systemPrompt: String, options: TextProcessingOptions, maxTokens: Int, temperature: Double
    ) async throws -> String {
        let options = await effectiveProviderOptions(options)
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
            let result = try await observedGeneration(request, providerID: providerID) {
                try await primary.generate(request)
            }
            try Task.checkCancellation()
            return result
        }
        return try await withLocalModelAccess {
            do {
                let result = try await GenerationFallback.run(
                    fallbackEnabled: options.fallbackToMLXOnEspressoFailure,
                    espresso: {
                        try await self.observedGeneration(request, providerID: providerID) {
                            try await primary.generate(request)
                        }
                    },
                    prepareForMLXFallback: { await primary.unload() },
                    mlx: {
                        let fallback = try await self.providers.create(id: options.fallbackProviderID, request: .inference)
                        try Task.checkCancellation()
                        return try await self.observedGeneration(fallbackRequest, providerID: options.fallbackProviderID) {
                            try await fallback.generate(fallbackRequest)
                        }
                    }
                )
                if result.usedMLX {
                    await Self.recordEspressoOutcome(.fallback)
                    log.info("[TextProcessor] ANE-LM failed; unloaded it and used the selected MLX model")
                } else {
                    await Self.clearEspressoOutcome()
                }
                return result.value
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as EspressoMLXFallbackError {
                await Self.recordEspressoOutcome(.unavailable)
                log.sensitive("[TextProcessor] ANE-LM and MLX fallback failed: \(error.details)")
                throw error
            } catch {
                if !options.fallbackToMLXOnEspressoFailure { await Self.recordEspressoOutcome(.failed) }
                throw error
            }
        }
    }

    package func generateWithScreenImage(
        prompt: String, systemPrompt: String, model: String, image: CGImage,
        maxTokens: Int, temperature: Double, providerID: String = "generation.mlx-image",
        modelLocations: FrozenGenerationLocations = .unresolved, modelVersions: FrozenGenerationVersions? = nil
    ) async throws -> String {
        let modelURL: URL?
        let frozenModel: ModelLocationLease?
        switch modelLocations {
        case .unresolved: modelURL = modelFiles.installedTextModelURL(model); frozenModel = nil
        case .frozen(_, let directory):
            modelURL = directory
            frozenModel = modelVersions?.directory ?? ModelLocationLease(directory)
        }
        let request = TextGenerationRequest(
            prompt: prompt, systemPrompt: systemPrompt, modelID: model, modelURL: modelURL,
            maxTokens: maxTokens, temperature: temperature, frozenModel: frozenModel
        )
        guard let imageProviders else { throw GenerationServiceError.unsupportedOperation }
        let provider = try await imageProviders.create(id: providerID, request: .inference)
        try Task.checkCancellation()
        let result = try await observedGeneration(request, providerID: providerID) {
            try await provider.generate(ImageGenerationRequest(text: request, image: image))
        }
        try Task.checkCancellation()
        return result
    }

    package func shouldUseScreenImage(options: TextProcessingOptions, image: CGImage?) -> Bool {
        guard imageProviders != nil, image != nil, options.screenContextMode == .multimodal,
              !options.useRemoteLLM, options.localLLMBackend == .mlx else { return false }
        return ScreenContextMode.supportsScreenImageContext(modelID: options.llmModel)
    }
}
