import UtterContracts

extension TextProcessor {
    package func prepareModel(_ proposed: TextProcessingOptions) async throws -> EspressoGenerationOutcome? {
        let options = await effectiveProviderOptions(proposed)
        let id = options.textProviderID ?? (options.useRemoteLLM ? "generation.remote" : options.localLLMBackend.rawValue)
        let usesANE = !options.useRemoteLLM && options.localLLMBackend == .espresso
        let request = generationRequest(prompt: "", systemPrompt: nil, options: options,
            maxTokens: 1, temperature: 0, usesANE: usesANE)
        return try await withLocalModelAccess {
            let primary = try await self.providers.create(id: id, request: .inference)
            guard usesANE else { try await primary.prepare(request); return nil }
            let result = try await GenerationFallback.run(fallbackEnabled: options.fallbackToMLXOnEspressoFailure,
                espresso: { try await primary.prepare(request) }, prepareForMLXFallback: { await primary.unload() },
                mlx: {
                    let fallback = try await self.providers.create(id: options.fallbackProviderID, request: .inference)
                    let request = self.generationRequest(prompt: "", systemPrompt: nil, options: options, maxTokens: 1, temperature: 0)
                    try await fallback.prepare(request)
                })
            return result.usedMLX ? .fallback : nil
        }
    }
}
