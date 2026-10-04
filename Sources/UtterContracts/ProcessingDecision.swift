import Foundation

package struct ProcessingDecision: Codable, Equatable, Sendable {
    package enum Disposition: String, Codable, Sendable { case direct, accepted, fallback, unverified, failed }
    package let disposition: Disposition
    package let reason: String?

    package init(_ disposition: Disposition, reason: String? = nil) {
        self.disposition = disposition
        self.reason = reason
    }
}

package struct GenerationTrace: Codable, Sendable {
    package let providerID: String
    package let modelID: String
    package let prompt: String
    package let systemPrompt: String?
    package let output: String?
    package let failure: String?
    package let maxTokens: Int
    package let temperature: Double
    package let elapsedMilliseconds: Double

    package init(request: TextGenerationRequest, providerID: String, output: String?,
                 failure: String?, elapsedMilliseconds: Double) {
        self.providerID = providerID
        modelID = request.modelID
        prompt = request.prompt
        systemPrompt = request.systemPrompt
        self.output = output
        self.failure = failure
        maxTokens = request.maxTokens
        temperature = request.temperature
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

package struct ProcessingTrace: Codable, Sendable {
    package let source: String?
    package let candidate: String?
    package let generations: [GenerationTrace]
    package let elapsedMilliseconds: Double

    package init(source: String?, candidate: String?, generations: [GenerationTrace], elapsedMilliseconds: Double) {
        self.source = source
        self.candidate = candidate
        self.generations = generations
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

package func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: ContinuousClock.now).components
    return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
}
