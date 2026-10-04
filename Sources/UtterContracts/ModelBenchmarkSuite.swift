import Foundation

package enum ModelBenchmarkSuite {
    package static func run(workloads: [(length: String, request: TextGenerationRequest)],
                            provider: any TextGenerationService) async throws -> ModelBenchmarkResult {
        var samples: [ModelBenchmarkSample] = []
        do {
            for workload in workloads {
                for _ in 0..<2 {
                    try Task.checkCancellation()
                    await provider.unload()
                    for cold in [true, false] {
                        try Task.checkCancellation()
                        let result = try await provider.benchmark(workload.request)
                        samples.append(ModelBenchmarkSample(length: workload.length, cold: cold, result: result))
                    }
                }
            }
            await provider.unload()
        } catch {
            await provider.unload()
            throw error
        }
        let load = samples.reduce(0) { $0 + $1.loadSeconds }
        let generation = samples.reduce(0) { $0 + $1.generationSeconds }
        let tokens = samples.reduce(0) { $0 + $1.outputTokens }
        let count = Double(max(1, samples.count))
        return ModelBenchmarkResult(loadTimeSeconds: load / count, generateTimeSeconds: generation / count,
            outputTokenEstimate: tokens, tokensPerSecond: generation > 0 ? Double(tokens) / generation : 0, samples: samples)
    }
}
