import Foundation
import XCTest
@testable import UtterContracts

final class ModelBenchmarkSuiteTests: XCTestCase {
    func testColdWarmGroupsUseProvidedFullRequestsAndDrainResources() async throws {
        let provider = BenchmarkProvider()
        let workloads = ["short", "medium", "long"].map { length in
            (length: length, request: TextGenerationRequest(prompt: "production-user-" + length,
                systemPrompt: "full production instructions", modelID: "installed", maxTokens: 640, temperature: 0))
        }
        let result = try await ModelBenchmarkSuite.run(workloads: workloads, provider: provider)
        XCTAssertEqual(result.samples.count, 12)
        XCTAssertEqual(result.groups.count, 6)
        XCTAssertTrue(result.groups.allSatisfy { $0.count == 2 })
        XCTAssertEqual(provider.requests.map(\.prompt), workloads.flatMap { Array(repeating: $0.request.prompt, count: 4) })
        XCTAssertTrue(provider.requests.allSatisfy { $0.systemPrompt == "full production instructions" && $0.maxTokens == 640 && $0.temperature == 0 })
        XCTAssertEqual(provider.unloads, 7)
        XCTAssertEqual(result.groups.first?.p50Seconds, 2)
        XCTAssertEqual(result.groups.first?.p95Seconds, 4)
    }

    func testFailureUnloadsAndDoesNotReturnAnIncompleteSuccess() async throws {
        let provider = BenchmarkProvider()
        provider.fail = true
        do {
            _ = try await ModelBenchmarkSuite.run(workloads: [("short", TextGenerationRequest(prompt: "full", modelID: "m"))], provider: provider)
            XCTFail("A failed benchmark was reported as complete")
        } catch { XCTAssertEqual(error as? GenerationServiceError, .modelUnavailable) }
        XCTAssertEqual(provider.unloads, 2)
        XCTAssertEqual(provider.requests.count, 1)
    }
}

private final class BenchmarkProvider: TextGenerationService, @unchecked Sendable {
    var requests: [TextGenerationRequest] = []
    var unloads = 0
    var fail = false
    func generate(_ request: TextGenerationRequest) async throws -> String { throw GenerationServiceError.unsupportedOperation }
    func benchmark(_ request: TextGenerationRequest) async throws -> ModelBenchmarkResult {
        requests.append(request)
        if fail { throw GenerationServiceError.modelUnavailable }
        return ModelBenchmarkResult(loadTimeSeconds: 1, generateTimeSeconds: Double(requests.count), outputTokenEstimate: 10, tokensPerSecond: 10)
    }
    func unload() async { unloads += 1 }
}
