import Foundation
import XCTest
import UtterContracts
@testable import UtterProcessing

final class GenerationFallbackTests: XCTestCase {
    private actor AsyncGate {
        private var isOpen = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private enum StubError: LocalizedError {
        case espresso
        case mlx

        var errorDescription: String? {
            switch self {
            case .espresso: return "espresso failed"
            case .mlx: return "mlx failed"
            }
        }
    }

    func testEspressoSuccessDoesNotRunMLXFallback() async throws {
        var ranMLX = false
        let result = try await GenerationFallback.run(
            espresso: { "espresso output" },
            mlx: {
                ranMLX = true
                return "mlx output"
            }
        )

        XCTAssertEqual(result.value, "espresso output")
        XCTAssertFalse(result.usedMLX)
        XCTAssertFalse(ranMLX)
    }

    func testEspressoFailureUsesMLXFallback() async throws {
        let result = try await GenerationFallback.run(
            espresso: { throw StubError.espresso },
            mlx: { "mlx output" }
        )

        XCTAssertEqual(result.value, "mlx output")
        XCTAssertTrue(result.usedMLX)
    }

    func testEspressoFailureReleasesANEStateBeforeMLXFallback() async throws {
        var espressoIsLoaded = true
        var espressoWasLoadedWhenMLXStarted = true

        let result: (value: String, usedMLX: Bool) = try await GenerationFallback.run(
            espresso: { throw StubError.espresso },
            prepareForMLXFallback: {
                espressoIsLoaded = false
            },
            mlx: {
                espressoWasLoadedWhenMLXStarted = espressoIsLoaded
                return "mlx output"
            }
        )

        XCTAssertEqual(result.value, "mlx output")
        XCTAssertTrue(result.usedMLX)
        XCTAssertFalse(espressoIsLoaded)
        XCTAssertFalse(espressoWasLoadedWhenMLXStarted)
    }

    func testDisabledFallbackDoesNotRunMLX() async {
        var preparedForFallback = false
        var ranMLX = false

        do {
            _ = try await GenerationFallback.run(
                fallbackEnabled: false,
                espresso: { throw StubError.espresso },
                prepareForMLXFallback: {
                    preparedForFallback = true
                },
                mlx: {
                    ranMLX = true
                    return "mlx output"
                }
            ) as (value: String, usedMLX: Bool)
            XCTFail("Expected the Espresso failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "espresso failed")
            XCTAssertFalse(preparedForFallback)
            XCTAssertFalse(ranMLX)
        }
    }

    func testDisabledFallbackCancellationDoesNotStartMLX() async {
        let espressoStarted = expectation(description: "Espresso started")
        let gate = AsyncGate()
        var ranMLX = false
        let task = Task {
            try await GenerationFallback.run(
                fallbackEnabled: false,
                espresso: {
                    espressoStarted.fulfill()
                    await gate.wait()
                    return "espresso output"
                },
                mlx: {
                    ranMLX = true
                    return "mlx output"
                }
            )
        }

        await fulfillment(of: [espressoStarted], timeout: 1)
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(ranMLX)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEspressoAndMLXFailuresPreserveBothDiagnostics() async {
        do {
            _ = try await GenerationFallback.run(
                espresso: { throw StubError.espresso },
                mlx: { throw StubError.mlx }
            ) as (value: String, usedMLX: Bool)
            XCTFail("Expected both local backends to fail")
        } catch let error as EspressoMLXFallbackError {
            XCTAssertTrue(error.details.contains("espresso failed"))
            XCTAssertTrue(error.details.contains("mlx failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

}
