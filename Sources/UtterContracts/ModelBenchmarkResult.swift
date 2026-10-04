import Foundation

package struct ModelBenchmarkResult: Sendable {
    package let samples: [ModelBenchmarkSample]
    package let loadTimeSeconds: Double
    package let generateTimeSeconds: Double
    package let outputTokenEstimate: Int
    package let tokensPerSecond: Double
    package init(loadTimeSeconds: Double, generateTimeSeconds: Double, outputTokenEstimate: Int, tokensPerSecond: Double,
                 samples: [ModelBenchmarkSample] = []) {
        self.loadTimeSeconds = loadTimeSeconds
        self.generateTimeSeconds = generateTimeSeconds
        self.outputTokenEstimate = outputTokenEstimate
        self.tokensPerSecond = tokensPerSecond
        self.samples = samples
    }
}

package struct ModelBenchmarkSample: Equatable, Sendable {
    package let length: String
    package let cold: Bool
    package let loadSeconds: Double
    package let generationSeconds: Double
    package let outputTokens: Int
    package init(length: String, cold: Bool, result: ModelBenchmarkResult) {
        self.length = length; self.cold = cold; loadSeconds = result.loadTimeSeconds
        generationSeconds = result.generateTimeSeconds; outputTokens = result.outputTokenEstimate
    }
}

package struct ModelBenchmarkGroup: Equatable, Sendable {
    package let length: String
    package let cold: Bool
    package let count: Int
    package let p50Seconds: Double
    package let p95Seconds: Double
}

extension ModelBenchmarkResult {
    package var groups: [ModelBenchmarkGroup] {
        ["short", "medium", "long"].flatMap { length in
            [true, false].compactMap { cold in
                let values = samples.filter { $0.length == length && $0.cold == cold }
                    .map { $0.loadSeconds + $0.generationSeconds }.sorted()
                guard !values.isEmpty else { return nil }
                return ModelBenchmarkGroup(length: length, cold: cold, count: values.count,
                    p50Seconds: values[Int(ceil(Double(values.count) * 0.5)) - 1],
                    p95Seconds: values[Int(ceil(Double(values.count) * 0.95)) - 1])
            }
        }
    }
}
