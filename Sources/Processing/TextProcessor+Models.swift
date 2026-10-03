import UtterModels
import UtterContracts
import Foundation
import MLX

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
            return try await withLocalModelAccess {
                switch backend {
                case .mlx:
                    return await llm.isLoaded
                case .espresso:
                    let espressoIsLoaded = await espressoLLM.isLoaded
                    let mlxIsLoaded = await llm.isLoaded
                    return espressoIsLoaded || mlxIsLoaded
                }
            }
        } catch {
            return false
        }
    }

    func unloadLLM() async {
        do {
            try await withLocalModelAccess {
                let llmWasLoaded = await llm.isLoaded
                let benchmarkWasLoaded = await benchmarkEngine.isLoaded
                let vlmWasLoaded = await vlm.isLoaded
                await llm.unload()
                await benchmarkEngine.unload()
                await espressoLLM.unload()
                await vlm.unload()
                if llmWasLoaded || benchmarkWasLoaded || vlmWasLoaded {
                    Memory.clearCache()
                }
            }
        } catch {
            Log.info("[TextProcessor] local model unload cancelled")
        }
    }

    func benchmarkLLM(modelID: String) async throws -> ModelBenchmarkResult {
        try await withLocalModelAccess {
            try Task.checkCancellation()
            do {
                let result = try await benchmarkEngine.benchmark(modelID: modelID)
                let wasLoaded = await benchmarkEngine.isLoaded
                await benchmarkEngine.unload()
                if wasLoaded { Memory.clearCache() }
                return result
            } catch {
                let wasLoaded = await benchmarkEngine.isLoaded
                await benchmarkEngine.unload()
                if wasLoaded { Memory.clearCache() }
                throw error
            }
        }
    }

    @discardableResult
    func warmUpLLM(
        model: String,
        backend: LocalLLMBackend,
        espressoModelPath: String,
        fallbackToMLXOnEspressoFailure: Bool
    ) async -> (loaded: Bool, errorMessage: String?, espressoOutcome: EspressoGenerationOutcome?) {
        do {
            return try await withLocalModelAccess {
                do {
                    switch backend {
                    case .mlx:
                        try await llm.loadModel(id: model)
                    case .espresso:
                        let result = try await Self.runEspressoWithMLXFallback(
                            fallbackEnabled: fallbackToMLXOnEspressoFailure,
                            espresso: { try await self.espressoLLM.loadModel(path: espressoModelPath) },
                            prepareForMLXFallback: { await self.espressoLLM.unload() },
                            mlx: { try await self.llm.loadModel(id: model) }
                        )
                        if result.usedMLX {
                            return (true, nil, .fallback)
                        }
                    }
                    return (true, nil, nil)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as EspressoMLXFallbackError {
                    Log.sensitive("[TextProcessor] ANE-LM and MLX warmup failed: \(error.details)")
                    Log.error("[TextProcessor] MLX fallback unavailable during warmup")
                    return (false, EspressoGenerationOutcome.unavailable.message, .unavailable)
                } catch {
                    Log.error("[TextProcessor] LLM warmup failed: \(error.localizedDescription)")
                    if backend == .espresso {
                        _ = await espressoLLM.consumeLastFailureMessage()
                        if !fallbackToMLXOnEspressoFailure {
                            return (false, EspressoGenerationOutcome.failed.message, .failed)
                        }
                    }
                    return (false, error.localizedDescription, nil)
                }
            }
        } catch is CancellationError {
            return (false, nil, nil)
        } catch {
            return (false, error.localizedDescription, nil)
        }
    }
}
