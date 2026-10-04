import Foundation
import UtterContracts

package enum ProcessingObservations {
    @TaskLocal package static var current: ProcessingObservation?
}

package final class ProcessingObservation: @unchecked Sendable {
    private let lock = NSLock()
    private let collectsBody: Bool
    private let started = ContinuousClock.now
    private var decision = ProcessingDecision(.accepted)
    private var source: String?
    private var candidate: String?
    private var generations: [GenerationTrace] = []
    private var providerID: String?

    package init(collectsBody: Bool = false) { self.collectsBody = collectsBody }

    package func record(source: String, candidate: String, decision: ProcessingDecision) {
        lock.lock()
        defer { lock.unlock() }
        self.decision = decision
        if collectsBody { self.source = source; self.candidate = candidate }
    }

    package func record(request: TextGenerationRequest, providerID: String, output: String?,
                        failure: String? = nil, elapsedMilliseconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        if output != nil { self.providerID = providerID }
        guard collectsBody else { return }
        generations.append(GenerationTrace(request: request, providerID: providerID,
            output: output, failure: failure, elapsedMilliseconds: elapsedMilliseconds))
    }

    package var lastSuccessfulProviderID: String? {
        lock.lock(); defer { lock.unlock() }
        return providerID
    }

    package func complete(source: String, candidate: String) {
        lock.lock()
        defer { lock.unlock() }
        guard collectsBody else { return }
        if self.source == nil { self.source = source }
        if self.candidate == nil { self.candidate = candidate }
    }

    package func snapshot() -> (decision: ProcessingDecision, trace: ProcessingTrace?) {
        lock.lock()
        defer { lock.unlock() }
        let trace = collectsBody ? ProcessingTrace(source: source, candidate: candidate,
            generations: generations, elapsedMilliseconds: elapsedMilliseconds(since: started)) : nil
        return (decision, trace)
    }
}
