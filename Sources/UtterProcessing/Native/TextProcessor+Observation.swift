import UtterContracts

extension TextProcessor {
    func observedGeneration(_ request: TextGenerationRequest, providerID: String,
                            operation: () async throws -> String) async throws -> String {
        let started = ContinuousClock.now
        do {
            let output = try await operation()
            try Task.checkCancellation()
            let elapsed = elapsedMilliseconds(since: started)
            GenerationTimingObservations.current?.record(GenerationTiming(stage: ProcessingObservations.generationStage,
                elapsedMilliseconds: elapsed, failed: false))
            ProcessingObservations.current?.record(request: request, providerID: providerID,
                output: output, elapsedMilliseconds: elapsed)
            return output
        } catch {
            let elapsed = elapsedMilliseconds(since: started)
            GenerationTimingObservations.current?.record(GenerationTiming(stage: ProcessingObservations.generationStage,
                elapsedMilliseconds: elapsed, failed: true))
            ProcessingObservations.current?.record(request: request, providerID: providerID,
                output: nil, failure: String(reflecting: type(of: error)),
                elapsedMilliseconds: elapsed)
            throw error
        }
    }
}
