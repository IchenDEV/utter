import UtterMediaContracts
import UtterData
import UtterModels
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterProcessing
import UtterPresentationContracts
import UtterContracts
import XCTest
import MLX
@testable import UtterPresentation

final class EspressoFallbackTests: XCTestCase {
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
        settings.espressoModelPath = "/models/Qwen3-new"

        XCTAssertFalse(EspressoFallbackPolicy.selectMLXIfNeeded(
            after: .fallback,
            settings: settings,
            expectedEspressoModelPath: "/models/Qwen3-old"
        ))
        XCTAssertEqual(settings.localLLMBackend, .espresso)
    }

    func testDisabledFallbackPreservesEspressoSelection() {
        let suiteName = "EspressoFallbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.fallbackToMLXOnEspressoFailure)
        settings.localLLMBackend = .espresso
        settings.fallbackToMLXOnEspressoFailure = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.fallbackToMLXOnEspressoFailure)

        XCTAssertFalse(EspressoFallbackPolicy.selectMLXIfNeeded(
            after: .fallback,
            settings: reloaded,
            expectedEspressoModelPath: reloaded.espressoModelPath
        ))
        XCTAssertEqual(reloaded.localLLMBackend, .espresso)
    }

    func testLocalizedFallbackMessagesMentionMLX() {
        for language in [UILanguage.english, .chinese] {
            XCTAssertTrue(Loc.string("status.espresso_fell_back_to_mlx", language: language).contains("MLX"))
            XCTAssertTrue(Loc.string("error.espresso_mlx_fallback_unavailable", language: language).contains("MLX"))
            XCTAssertFalse(Loc.string("model.espresso.auto_fallback", language: language).isEmpty)
        }
    }

    func testRealANEFailureFallsBackToInstalledMLX() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_ANE_MLX_FALLBACK_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_ANE_MLX_FALLBACK_INTEGRATION=1 to run")
        }
        guard let modelPath = environment["OPENTYPE_ANE_FAILURE_MODEL"],
              let mlxModel = environment["OPENTYPE_MLX_MODEL"] else {
            throw XCTSkip("Set OPENTYPE_ANE_FAILURE_MODEL and OPENTYPE_MLX_MODEL")
        }

        var options = TextProcessingOptions(settings: AppSettings.shared, inputLanguage: .english)
        options.useRemoteLLM = false
        options.localLLMBackend = .espresso
        options.espressoModelPath = modelPath
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
                    outcome = await processor.consumeEspressoOutcome()
                    let espresso = try await processor.providers.create(id: "generation.ane", request: .inference)
                    let espressoIsLoaded = await espresso.isLoaded
                    XCTAssertFalse(espressoIsLoaded)
                    baselineFootprint = currentMemoryFootprint()
                    options.localLLMBackend = .mlx
                }
            }
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
