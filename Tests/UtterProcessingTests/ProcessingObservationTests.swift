import Foundation
import UtterContracts
import XCTest
@testable import UtterProcessing

final class ProcessingObservationTests: XCTestCase {
    func testProductionObservationKeepsDecisionWithoutRetainingBodyOrCredentials() throws {
        let observation = ProcessingObservation()
        observation.record(request: request("private-prompt"), providerID: "fixture", output: "private-output",
            elapsedMilliseconds: 2)
        observation.record(source: "private-source", candidate: "private-candidate",
            decision: ProcessingDecision(.fallback, reason: "protected_token_change"))
        let snapshot = observation.snapshot()
        XCTAssertEqual(snapshot.decision.disposition, .fallback)
        XCTAssertEqual(snapshot.decision.reason, "protected_token_change")
        XCTAssertEqual(observation.lastSuccessfulProviderID, "fixture")
        XCTAssertNil(snapshot.trace)
    }

    func testOptInTraceDistinguishesGeneratedCandidateAndDecision() throws {
        let observation = ProcessingObservation(collectsBody: true)
        observation.record(request: request("synthetic"), providerID: "fixture", output: "<think>x</think>4 件事",
            elapsedMilliseconds: 2)
        observation.record(source: "三件事", candidate: "4 件事",
            decision: ProcessingDecision(.fallback, reason: "protected_token_change"))
        let trace = try XCTUnwrap(observation.snapshot().trace)
        XCTAssertEqual(trace.source, "三件事")
        XCTAssertEqual(trace.candidate, "4 件事")
        XCTAssertEqual(trace.generations.first?.output, "<think>x</think>4 件事")
        let json = String(decoding: try JSONEncoder().encode(trace), as: UTF8.self)
        XCTAssertFalse(json.contains("secret-api-key"))
        XCTAssertFalse(json.contains("private.example"))
    }

    func testConcurrentTaskLocalScopesCannotShareCandidates() async {
        let results = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for label in ["first", "second"] {
                group.addTask {
                    let observation = ProcessingObservation(collectsBody: true)
                    return await ProcessingObservations.$current.withValue(observation) {
                        await Task.yield()
                        ProcessingObservations.current?.record(source: label, candidate: label,
                            decision: ProcessingDecision(.accepted))
                        return observation.snapshot().trace?.candidate
                    }
                }
            }
            var results: [String] = []
            for await result in group { if let result { results.append(result) } }
            return results
        }
        XCTAssertEqual(Set(results), Set(["first", "second"]))
        XCTAssertNil(ProcessingObservations.current)
    }

    private func request(_ prompt: String) -> TextGenerationRequest {
        TextGenerationRequest(prompt: prompt, systemPrompt: "system", modelID: "fixture",
            remote: RemoteGenerationConfiguration(baseURL: "https://private.example", apiKey: "secret-api-key", provider: .openai))
    }
}
