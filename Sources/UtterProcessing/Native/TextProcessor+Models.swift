import UtterContracts
import Foundation

extension TextProcessor {
    package func withLocalModelAccess<Value>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        try await localModelAccessGate.withAccess(operation)
    }

    package static func withEspressoOutcomeTracking<Value>(
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        if espressoGenerationTracker != nil {
            return try await operation()
        }
        return try await $espressoGenerationTracker.withValue(EspressoGenerationTracker()) {
            try await operation()
        }
    }

    package static func recordEspressoOutcome(_ outcome: EspressoGenerationOutcome) async {
        await espressoGenerationTracker?.record(outcome)
    }

    package static func clearEspressoOutcome() async {
        await espressoGenerationTracker?.clear()
    }

    package func consumeEspressoOutcome() async -> EspressoGenerationOutcome? {
        await Self.espressoGenerationTracker?.consume()
    }

    package func isLLMReady(for backend: LocalLLMBackend) async -> Bool {
        do {
            let primary = try await providers.create(id: backend.rawValue, request: .inference)
            if await primary.isLoaded { return true }
            guard backend == .espresso else { return false }
            let fallback = try await providers.create(id: "generation.mlx", request: .inference)
            return await fallback.isLoaded
        } catch { return false }
    }

    package func unloadLLM() async {
        let descriptors = await providers.descriptors
        for descriptor in descriptors where descriptor.id.hasPrefix("generation.") {
            for purpose in [GenerationPurpose.inference, .benchmark] {
                if let provider = try? await providers.create(id: descriptor.id, request: purpose) { await provider.unload() }
            }
        }
        guard let imageProviders else { return }
        let imageDescriptors = await imageProviders.descriptors
        for descriptor in imageDescriptors {
            if let provider = try? await imageProviders.create(id: descriptor.id, request: .inference) { await provider.unload() }
        }
    }

    @discardableResult
    package func warmUpLLM(
        model: String, backend: LocalLLMBackend, espressoModelPath: String,
        fallbackToMLXOnEspressoFailure: Bool
    ) async -> (loaded: Bool, errorMessage: String?, espressoOutcome: EspressoGenerationOutcome?) {
        let primaryRequest = TextGenerationRequest(
            prompt: "", modelID: model,
            modelURL: backend == .espresso
                ? URL(fileURLWithPath: NSString(string: espressoModelPath).expandingTildeInPath)
                : modelFiles.installedTextModelURL(model)
        )
        let fallbackRequest = TextGenerationRequest(prompt: "", modelID: model, modelURL: modelFiles.installedTextModelURL(model))
        do {
            return try await withLocalModelAccess {
                let primary = try await self.providers.create(id: backend.rawValue, request: .inference)
                try Task.checkCancellation()
                do {
                    if backend == .espresso {
                        let result = try await GenerationFallback.run(
                            fallbackEnabled: fallbackToMLXOnEspressoFailure,
                            espresso: { try await primary.prepare(primaryRequest) },
                            prepareForMLXFallback: { await primary.unload() },
                            mlx: {
                                let fallback = try await self.providers.create(id: "generation.mlx", request: .inference)
                                try Task.checkCancellation()
                                try await fallback.prepare(fallbackRequest)
                            }
                        )
                        return (true, nil, result.usedMLX ? .fallback : nil)
                    }
                    try await primary.prepare(primaryRequest)
                    try Task.checkCancellation()
                    return (true, nil, nil)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as EspressoMLXFallbackError {
                    log.sensitive("[TextProcessor] ANE-LM and MLX warmup failed: \(error.details)")
                    return (false, EspressoGenerationOutcome.unavailable.message, .unavailable)
                } catch {
                    if backend == .espresso && !fallbackToMLXOnEspressoFailure {
                        return (false, EspressoGenerationOutcome.failed.message, .failed)
                    }
                    return (false, error.localizedDescription, nil)
                }
            }
        } catch is CancellationError {
            return (false, nil, nil)
        } catch { return (false, error.localizedDescription, nil) }
    }
}
