import Foundation
import MLX

actor LocalModelAccessGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var isOccupied = false
    private var waiters: [Waiter] = []

    var waitingTaskCount: Int { waiters.count }

    func acquire() async throws {
        try Task.checkCancellation()
        guard isOccupied else {
            isOccupied = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        }, onCancel: {
            Task { await self.cancelWaiter(id: id) }
        })
    }

    func release() {
        guard !waiters.isEmpty else {
            isOccupied = false
            return
        }
        waiters.removeFirst().continuation.resume()
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

extension TextProcessor {
    func withLocalModelAccess<Value>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        if Self.hasLocalModelAccess {
            return try await operation()
        }

        try await localModelAccessGate.acquire()
        do {
            let value = try await Self.$hasLocalModelAccess.withValue(true) {
                try Task.checkCancellation()
                return try await operation()
            }
            await localModelAccessGate.release()
            return value
        } catch {
            await localModelAccessGate.release()
            throw error
        }
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

    func benchmarkLLM(modelID: String) async throws -> LLMEngine.BenchmarkResult {
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
                            mlx: { try await self.llm.loadModel(id: model) }
                        )
                        if result.usedMLX {
                            _ = await espressoLLM.consumeLastFailureMessage()
                            return (true, nil, .fallback)
                        }
                    }
                    return (true, nil, nil)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as EspressoMLXFallbackError {
                    Log.sensitive("[TextProcessor] ANE-LM and MLX warmup failed: \(error.details)")
                    Log.error("[TextProcessor] MLX fallback unavailable during warmup")
                    _ = await espressoLLM.consumeLastFailureMessage()
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
