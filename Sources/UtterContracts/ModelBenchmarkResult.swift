import Foundation

package struct ModelBenchmarkResult: Sendable {
    package let loadTimeSeconds: Double
    package let generateTimeSeconds: Double
    package let outputTokenEstimate: Int
    package let tokensPerSecond: Double
    package init(loadTimeSeconds: Double, generateTimeSeconds: Double, outputTokenEstimate: Int, tokensPerSecond: Double) {
        self.loadTimeSeconds = loadTimeSeconds
        self.generateTimeSeconds = generateTimeSeconds
        self.outputTokenEstimate = outputTokenEstimate
        self.tokensPerSecond = tokensPerSecond
    }
}
