import XCTest
import MLX
@testable import OpenType

final class EspressoFallbackTests: XCTestCase {
    private final class WeakTrackerBox {
        weak var value: EspressoGenerationTracker?
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
        let result = try await TextProcessor.runEspressoWithMLXFallback(
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
        let result = try await TextProcessor.runEspressoWithMLXFallback(
            espresso: { throw StubError.espresso },
            mlx: { "mlx output" }
        )

        XCTAssertEqual(result.value, "mlx output")
        XCTAssertTrue(result.usedMLX)
    }

    func testCancellationDoesNotStartMLXFallback() async {
        let espressoStarted = expectation(description: "Espresso started")
        var ranMLX = false
        let task = Task {
            try await TextProcessor.runEspressoWithMLXFallback(
                espresso: {
                    espressoStarted.fulfill()
                    try await Task.sleep(for: .seconds(10))
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
            _ = try await TextProcessor.runEspressoWithMLXFallback(
                espresso: { throw StubError.espresso },
                mlx: { throw StubError.mlx }
            ) as (value: String, usedMLX: Bool)
            XCTFail("Expected both local backends to fail")
        } catch let error as TextProcessor.EspressoMLXFallbackError {
            XCTAssertTrue(error.details.contains("espresso failed"))
            XCTAssertTrue(error.details.contains("mlx failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOutcomeTrackingIsRequestScoped() async {
        let processor = TextProcessor()
        var first: EspressoGenerationOutcome?
        var second: EspressoGenerationOutcome?

        await TextProcessor.withEspressoOutcomeTracking {
            await TextProcessor.recordEspressoOutcome(.fallback)
            first = await processor.consumeEspressoOutcome()
        }
        await TextProcessor.withEspressoOutcomeTracking {
            second = await processor.consumeEspressoOutcome()
        }

        XCTAssertEqual(first, .fallback)
        XCTAssertNil(second)
    }

    func testOutcomeTrackerIsReleasedAfterRequestCompletes() async {
        let box = WeakTrackerBox()

        await TextProcessor.withEspressoOutcomeTracking {
            box.value = TextProcessor.espressoGenerationTracker
            XCTAssertNotNil(box.value)
        }

        XCTAssertNil(box.value)
    }

    func testFallbackOutcomeSwitchesPersistedBackendToMLX() {
        let suiteName = "EspressoFallbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.localLLMBackend = .espresso

        XCTAssertTrue(EspressoFallbackPolicy.selectMLXIfNeeded(
            after: .fallback,
            settings: settings,
            expectedEspressoModelPath: settings.espressoModelPath
        ))
        XCTAssertEqual(settings.localLLMBackend, .mlx)
        XCTAssertEqual(defaults.string(forKey: "localLLMBackend"), LocalLLMBackend.mlx.rawValue)
    }

    func testFallbackOutcomePreservesNewerEspressoSelection() {
        let suiteName = "EspressoFallbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.localLLMBackend = .espresso
        settings.espressoModelPath = "/models/new.esp"

        XCTAssertFalse(EspressoFallbackPolicy.selectMLXIfNeeded(
            after: .fallback,
            settings: settings,
            expectedEspressoModelPath: "/models/old.esp"
        ))
        XCTAssertEqual(settings.localLLMBackend, .espresso)
    }

    func testLocalizedFallbackMessagesMentionMLX() {
        for language in [UILanguage.english, .chinese] {
            XCTAssertTrue(Loc.string("status.espresso_fell_back_to_mlx", language: language).contains("MLX"))
            XCTAssertTrue(Loc.string("error.espresso_mlx_fallback_unavailable", language: language).contains("MLX"))
        }
    }

    func testRealEspressoFailureFallsBackToInstalledMLX() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_ESPRESSO_MLX_FALLBACK_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_ESPRESSO_MLX_FALLBACK_INTEGRATION=1 to run")
        }
        guard let bundlePath = environment["OPENTYPE_ESPRESSO_BUNDLE"],
              let mlxModel = environment["OPENTYPE_MLX_MODEL"] else {
            throw XCTSkip("Set OPENTYPE_ESPRESSO_BUNDLE and OPENTYPE_MLX_MODEL")
        }

        var options = TextProcessingOptions(settings: AppSettings.shared, inputLanguage: .english)
        options.useRemoteLLM = false
        options.localLLMBackend = .espresso
        options.espressoModelPath = bundlePath
        options.llmModel = mlxModel

        let processor = TextProcessor()
        let initialFootprint = currentMemoryFootprint()
        let iterations = Int(environment["OPENTYPE_FALLBACK_ITERATIONS"] ?? "1") ?? 1
        var output = ""
        var outcome: EspressoGenerationOutcome?
        var baselineFootprint: UInt64?
        try await TextProcessor.withEspressoOutcomeTracking {
            for index in 0..<max(iterations, 1) {
                output = try await processor.generateText(
                    prompt: "Reply with exactly OK.",
                    systemPrompt: "Return only the requested answer.",
                    options: options,
                    maxTokens: 8,
                    temperature: 0
                )
                if index == 0 {
                    baselineFootprint = currentMemoryFootprint()
                    options.localLLMBackend = .mlx
                }
            }
            outcome = await processor.consumeEspressoOutcome()
        }

        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(outcome, .fallback)
        if iterations > 1, let baselineFootprint {
            let currentFootprint = currentMemoryFootprint()
            let growth = currentFootprint > baselineFootprint
                ? currentFootprint - baselineFootprint
                : 0
            XCTAssertLessThan(growth, 384 * 1_024 * 1_024, "Repeated MLX requests retained \(growth) bytes")
        }
        await processor.unloadLLM()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertLessThan(Memory.activeMemory, 1 * 1_024 * 1_024)
        XCTAssertEqual(Memory.cacheMemory, 0)
        let footprintAfterUnload = currentMemoryFootprint()
        let retainedAfterUnload = footprintAfterUnload > initialFootprint
            ? footprintAfterUnload - initialFootprint
            : 0
        XCTAssertLessThan(
            retainedAfterUnload,
            1_024 * 1_024 * 1_024,
            "Local model unload retained \(retainedAfterUnload) bytes"
        )
    }
}

private func currentMemoryFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}
