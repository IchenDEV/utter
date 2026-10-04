import UtterContracts

extension TextProcessor {
    func observedGeneration(_ request: TextGenerationRequest, providerID: String,
                            operation: () async throws -> String) async throws -> String {
        let started = ContinuousClock.now
        do {
            let output = try await operation()
            try Task.checkCancellation()
            ProcessingObservations.current?.record(request: request, providerID: providerID,
                output: output, elapsedMilliseconds: elapsedMilliseconds(since: started))
            return output
        } catch {
            ProcessingObservations.current?.record(request: request, providerID: providerID,
                output: nil, failure: String(reflecting: type(of: error)),
                elapsedMilliseconds: elapsedMilliseconds(since: started))
            throw error
        }
    }
}
