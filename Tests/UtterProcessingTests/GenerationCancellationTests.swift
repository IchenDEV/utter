import Foundation
import XCTest
import UtterContracts
@testable import UtterProcessing

final class GenerationCancellationTests: XCTestCase {
    func testAlreadyCancelledOperationDoesNotStartEitherProvider() async {
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await GenerationFallback.run(
                espresso: { XCTFail("Cancelled operation started primary provider"); return "primary" },
                mlx: { XCTFail("Cancelled operation started fallback provider"); return "fallback" }
            )
        }
        do { _ = try await operation.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCancellationDuringPrimaryCleanupDoesNotStartFallback() async {
        let entered = expectation(description: "Primary cleanup entered")
        let cleanup = CleanupBarrier()
        let operation = Task {
            try await GenerationFallback.run(
                espresso: { () async throws -> String in throw GenerationServiceError.unsupportedOperation },
                prepareForMLXFallback: { entered.fulfill(); await cleanup.wait() },
                mlx: { XCTFail("Cancelled cleanup started fallback provider"); return "fallback" }
            )
        }
        await fulfillment(of: [entered], timeout: 1)
        operation.cancel()
        await cleanup.release()
        do { _ = try await operation.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}

private actor CleanupBarrier {
    private var released = false
    private var held: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { held = $0 }
    }
    func release() { released = true; held?.resume(); held = nil }
}
