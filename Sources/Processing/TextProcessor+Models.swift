import UtterProcessing
import UtterModels
import UtterContracts
import Foundation

extension TextProcessor {
    func withLocalModelAccess<Value>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        try await localModelAccessGate.withAccess(operation)
    }

    static func withEspressoOutcomeTracking<Value>(
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        if espressoGenerationTracker != nil {
            return try await operation()
        }
        return try await $espressoGenerationTracker.withValue(EspressoGenerationTracker()) {
            try await operation()
        }
    }

    static func recordEspressoOutcome(_ outcome: EspressoGenerationOutcome) async {
        await espressoGenerationTracker?.record(outcome)
    }

    static func clearEspressoOutcome() async {
        await espressoGenerationTracker?.clear()
    }

    func consumeEspressoOutcome() async -> EspressoGenerationOutcome? {
        await Self.espressoGenerationTracker?.consume()
    }

    func isLLMReady(for backend: LocalLLMBackend) async -> Bool {
        do {
            let primary = try await providers.create(id: backend.rawValue, request: .inference)
            if await primary.isLoaded { return true }
            guard backend == .espresso else { return false }
            let fallback = try await providers.create(id: "generation.mlx", request: .inference)
            return await fallback.isLoaded
        } catch { return false }
    }

    func unloadLLM() async {
        let descriptors = await providers.descriptors
        for descriptor in descriptors where descriptor.id.hasPrefix("generation.") {
            for purpose in [GenerationPurpose.inference, .benchmark] {
                if let provider = try? await providers.create(id: descriptor.id, request: purpose) { await provider.unload() }
            }
        }
        let imageDescriptors = await imageProviders.descriptors
        for descriptor in imageDescriptors {
            if let provider = try? await imageProviders.create(id: descriptor.id, request: .inference) { await provider.unload() }
        }
    }

    func benchmarkLLM(modelID: String) async throws -> ModelBenchmarkResult {
        let request = TextGenerationRequest(prompt: "", modelID: modelID, modelURL: modelFiles.installedTextModelURL(modelID))
        let provider = try await providers.create(id: "generation.mlx", request: .benchmark)
        try Task.checkCancellation()
        return try await provider.benchmark(request)
    }

    @discardableResult
    func warmUpLLM(
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
                        let result = try await Self.runEspressoWithMLXFallback(
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
                    Log.sensitive("[TextProcessor] ANE-LM and MLX warmup failed: \(error.details)")
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
