import Foundation
import XCTest
@testable import OpenType

final class ANELMRuntimeTests: XCTestCase {
    func testModelValidationRejectsTruncatedMissingAndWrongDtypeWeights() async throws {
        let valid = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: valid) }
        try await EspressoLLMEngine.validateModelDirectory(at: valid)

        let truncated = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: truncated) }
        try Data([1]).write(to: truncated.appendingPathComponent("model.safetensors"))
        await XCTAssertThrowsErrorAsync(try await EspressoLLMEngine.validateModelDirectory(at: truncated))

        let missing = try makeSyntheticQwen3Directory(omitting: "model.layers.0.self_attn.q_proj.weight")
        defer { try? FileManager.default.removeItem(at: missing) }
        await XCTAssertThrowsErrorAsync(try await EspressoLLMEngine.validateModelDirectory(at: missing))

        let wrongDtype = try makeSyntheticQwen3Directory(dtype: "F16")
        defer { try? FileManager.default.removeItem(at: wrongDtype) }
        await XCTAssertThrowsErrorAsync(try await EspressoLLMEngine.validateModelDirectory(at: wrongDtype))
    }

    func testModelValidationRejectsUnsupportedConfigAndMissingTokenizer() async throws {
        let directory = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(#"{"model_type":"llama"}"#.utf8)
            .write(to: directory.appendingPathComponent("config.json"))
        await XCTAssertThrowsErrorAsync(try await EspressoLLMEngine.validateModelDirectory(at: directory))

        try writeSyntheticQwen3Config(to: directory)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("tokenizer.json"))
        await XCTAssertThrowsErrorAsync(try await EspressoLLMEngine.validateModelDirectory(at: directory))

        let invalidTokenizer = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: invalidTokenizer) }
        try Data("{}".utf8).write(to: invalidTokenizer.appendingPathComponent("tokenizer.json"))
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: invalidTokenizer)
        )

        let unsafeTokenizer = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: unsafeTokenizer) }
        try rewriteSyntheticTokenizer(at: unsafeTokenizer) {
            $0["normalizer"] = ["type": "Bogus"]
        }
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: unsafeTokenizer)
        )

        let outOfRangeTokenizer = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: outOfRangeTokenizer) }
        try rewriteSyntheticTokenizer(at: outOfRangeTokenizer) {
            var addedTokens = $0["added_tokens"] as? [[String: Any]] ?? []
            addedTokens[0]["id"] = syntheticANEModelVocabularySize
            $0["added_tokens"] = addedTokens
        }
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: outOfRangeTokenizer)
        )

        let missingUnknownToken = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: missingUnknownToken) }
        try rewriteSyntheticTokenizerConfig(at: missingUnknownToken) {
            $0["unk_token"] = "<missing>"
        }
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: missingUnknownToken)
        )

        let missingChatToken = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: missingChatToken) }
        try rewriteSyntheticTokenizer(at: missingChatToken) {
            var addedTokens = $0["added_tokens"] as? [[String: Any]] ?? []
            addedTokens[2]["content"] = "<missing-chat-start>"
            $0["added_tokens"] = addedTokens
        }
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: missingChatToken)
        )

        let nonSpecialChatToken = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: nonSpecialChatToken) }
        try rewriteSyntheticTokenizer(at: nonSpecialChatToken) {
            var addedTokens = $0["added_tokens"] as? [[String: Any]] ?? []
            addedTokens[3]["special"] = false
            $0["added_tokens"] = addedTokens
        }
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: nonSpecialChatToken)
        )

        let wrongEndToken = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: wrongEndToken) }
        try rewriteSyntheticTokenizerConfig(at: wrongEndToken) {
            $0["eos_token"] = "<unk>"
        }
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: wrongEndToken)
        )

        let invalidByteToken = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: invalidByteToken) }
        try rewriteSyntheticTokenizer(at: invalidByteToken) {
            var model = $0["model"] as? [String: Any] ?? [:]
            var vocabulary = model["vocab"] as? [String: Any] ?? [:]
            vocabulary["☃"] = vocabulary.removeValue(forKey: "!") ?? 0
            model["vocab"] = vocabulary
            $0["model"] = model
        }
        await XCTAssertThrowsErrorAsync(
            try await EspressoLLMEngine.validateModelDirectory(at: invalidByteToken)
        )

        let invalidHeads = try makeSyntheticQwen3Directory()
        defer { try? FileManager.default.removeItem(at: invalidHeads) }
        try writeSyntheticQwen3Config(to: invalidHeads, qHeads: 3, kvHeads: 2)
        await XCTAssertThrowsErrorAsync(try await EspressoLLMEngine.validateModelDirectory(at: invalidHeads))
    }

    func testQwenPromptDisablesThinkingBeforeGeneration() {
        let prompt = EspressoLLMEngine.formatPrompt(
            user: "Return JSON.",
            system: "Do not explain.",
            modelName: "Qwen3"
        )

        XCTAssertTrue(prompt.hasSuffix(
            "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        ))
    }

    func testContextWindowGuardReservesGeneratedCacheSlots() {
        XCTAssertTrue(EspressoLLMEngine.requestFitsContextWindow(
            promptTokenCount: 2_048,
            maxTokens: 1
        ))
        XCTAssertTrue(EspressoLLMEngine.requestFitsContextWindow(
            promptTokenCount: 2_047,
            maxTokens: 2
        ))
        XCTAssertFalse(EspressoLLMEngine.requestFitsContextWindow(
            promptTokenCount: 2_049,
            maxTokens: 1
        ))
        XCTAssertFalse(EspressoLLMEngine.requestFitsContextWindow(
            promptTokenCount: 2_048,
            maxTokens: 2
        ))
        XCTAssertFalse(EspressoLLMEngine.requestFitsContextWindow(
            promptTokenCount: 1,
            maxTokens: 2_049
        ))
    }

    func testRealGenerationLifecycleWhenModelIsProvided() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["UTTER_ANE_TEST_MODEL"],
              !modelPath.isEmpty else {
            throw XCTSkip("Set UTTER_ANE_TEST_MODEL to a complete local Qwen3 model directory")
        }

        let iterations = Int(
            ProcessInfo.processInfo.environment["UTTER_ANE_TEST_ITERATIONS"] ?? "20"
        ) ?? 20
        XCTAssertGreaterThanOrEqual(iterations, 20)
        let baselineResidentSize = try residentSizeKB()
        let engine = EspressoLLMEngine()
        var residentSamples: [Int] = []
        var unloadMinima: [Int] = []
        var lifecycleGrowth: [Int] = []
        let lifecycleCount = 3

        for lifecycle in 0..<lifecycleCount {
            try await engine.loadModel(path: modelPath)
            let requestCount = iterations / lifecycleCount
                + (lifecycle < iterations % lifecycleCount ? 1 : 0)
            var lifecycleSamples: [Int] = []
            for requestIndex in 0..<requestCount {
                let verifiesStructuredCommandOutput = lifecycle == 0 && requestIndex == 0
                let output = try await engine.generate(
                    prompt: verifiesStructuredCommandOutput
                        ? #"Return exactly this JSON object: {"action":"none","confidence":1}"#
                        : "用一句中文回答：苹果神经引擎能运行本地语言模型吗？",
                    systemPrompt: verifiesStructuredCommandOutput
                        ? "Return only valid JSON."
                        : "只输出简短答案。",
                    maxTokens: verifiesStructuredCommandOutput ? 64 : 16,
                    temperature: verifiesStructuredCommandOutput ? 0 : 0.2
                )
                XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(output.localizedCaseInsensitiveContains("<think"))
                XCTAssertFalse(output.localizedCaseInsensitiveContains("</think>"))
                if verifiesStructuredCommandOutput {
                    XCTAssertNotNil(SpokenEditCommandLLMResolver.resolution(from: output))
                }
                let sample = try residentSizeKB()
                residentSamples.append(sample)
                lifecycleSamples.append(sample)
            }

            if lifecycle == lifecycleCount - 1 {
                let cancellation = Task {
                    try await engine.generate(
                        prompt: "请详细解释本地语言模型。",
                        systemPrompt: "详细回答。",
                        maxTokens: 512,
                        temperature: 0.2
                    )
                }
                try await Task.sleep(for: .milliseconds(100))
                cancellation.cancel()
                do {
                    _ = try await cancellation.value
                    XCTFail("Expected ANE-LM generation cancellation")
                } catch is CancellationError { }
            }

            let loadedResidentSize = try XCTUnwrap(lifecycleSamples.max())
            let growth = max(0, try XCTUnwrap(lifecycleSamples.last) - XCTUnwrap(lifecycleSamples.first))
            lifecycleGrowth.append(growth)
            XCTAssertLessThanOrEqual(growth, 16 * 1024)
            await engine.unload()
            var unloadSamples: [Int] = []
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(100))
                unloadSamples.append(try residentSizeKB())
            }
            let unloadedResidentSize = try XCTUnwrap(unloadSamples.min())
            unloadMinima.append(unloadedResidentSize)
            XCTAssertGreaterThanOrEqual(loadedResidentSize - unloadedResidentSize, 512 * 1024)
            let isLoaded = await engine.isLoaded
            XCTAssertFalse(isLoaded)
        }

        let unloadGrowth = max(0, try XCTUnwrap(unloadMinima.last) - XCTUnwrap(unloadMinima.first))
        print(
            "ANE-LM RSS samples KB: \(residentSamples); lifecycle growth KB: \(lifecycleGrowth); "
                + "baseline KB: \(baselineResidentSize); unload minima KB: \(unloadMinima); "
                + "net unload growth KB: \(unloadGrowth)"
        )
        XCTAssertLessThanOrEqual(unloadGrowth, 128 * 1024)
    }

    private func residentSizeKB() throws -> Int {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, let size = Int(value) else {
            throw NSError(domain: "ANELMRuntimeTests", code: 1)
        }
        return size
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch { }
}
