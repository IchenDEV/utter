import XCTest
@testable import OpenType

final class TextProcessorFallbackTests: XCTestCase {
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

    func testSmartFormatDoesNotUsePreparedFallbackByDefault() {
        XCTAssertFalse(TextProcessor.defaultAllowsPreparedFallback)
    }

    func testGeneratedOutputFallsBackOnlyWhenExplicitlyProvided() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.cleanGeneratedOutput("<think>reasoning</think>", inputLanguage: .english),
            ""
        )
        XCTAssertEqual(
            processor.cleanGeneratedOutput(
                "<think>reasoning</think>",
                inputLanguage: .english,
                fallback: "raw transcript"
            ),
            "raw transcript"
        )
    }

    func testRejectedOutputFallbackRespectsPreparedFallbackPolicy() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.rejectedOutputFallback(
                "raw transcript",
                allowsGuardFallback: true
            ),
            "raw transcript"
        )
        XCTAssertEqual(
            processor.rejectedOutputFallback(
                "raw transcript",
                allowsGuardFallback: false
            ),
            ""
        )
    }

    func testCustomTransformationUsesNeutralUserPromptAndExplicitPolicy() {
        let settings = AppSettings.shared
        var options = TextProcessingOptions(settings: settings, inputLanguage: .english)
        options.useCustomSystemPrompt = true
        options.customSystemPrompt = "Summarize concisely."

        XCTAssertEqual(options.fidelityPolicy, .boundedCustomTransformation)
        let prompt = TextProcessor().formattingUserPrompt(
            text: "A long raw transcript",
            options: options
        )
        XCTAssertTrue(prompt.contains("Apply the custom instructions"))
        XCTAssertFalse(prompt.contains("Never guess missing content"))
    }

    func testGeneratedOutputUsesFinalSectionAfterAnalysisScaffold() {
        let processor = TextProcessor()
        let output = """
        Analysis:
        The user wants a clean status update.

        Final:
        Ship the release notes today.
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(output, inputLanguage: .english),
            "Ship the release notes today."
        )
    }

    func testGeneratedOutputUsesTaggedFinalAfterThinkingScaffold() {
        let processor = TextProcessor()
        let output = """
        <analysis>Plan the rewrite.</analysis>
        <final>今天下午同步发布计划。</final>
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(output, inputLanguage: .chinese),
            "今天下午同步发布计划。"
        )
    }

    func testGeneratedOutputUsesCaseInsensitiveTaggedFinalScaffold() {
        let processor = TextProcessor()
        let output = """
        <ANALYSIS stage="draft">Plan the rewrite.</ANALYSIS>
        <FINAL_ANSWER source="model">Ship the release notes today.</FINAL_ANSWER>
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(output, inputLanguage: .english),
            "Ship the release notes today."
        )
    }

    func testGeneratedOutputStripsCaseInsensitiveThinkingOnlyScaffold() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.cleanGeneratedOutput("<THINK stage=\"draft\">reasoning</THINK>", inputLanguage: .english),
            ""
        )
        XCTAssertEqual(
            processor.cleanGeneratedOutput(
                "<THINK stage=\"draft\">reasoning</THINK>",
                inputLanguage: .english,
                fallback: "raw transcript"
            ),
            "raw transcript"
        )
    }

    func testGeneratedOutputUsesLocalizedFinalSectionAfterThinkingScaffold() {
        let processor = TextProcessor()
        let chinese = """
        分析：
        用户要一个简洁的发布同步。

        最终：
        今天下午同步发布计划。
        """
        let japanese = """
        分析:
        最終文だけを出す必要がある。

        最終:
        金曜の午後に会議します。
        """
        let korean = """
        분석:
        최종 문장만 출력해야 한다.

        최종:
        금요일 오후에 회의합니다.
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(chinese, inputLanguage: .chinese),
            "今天下午同步发布计划。"
        )
        XCTAssertEqual(
            processor.cleanGeneratedOutput(japanese, inputLanguage: .japanese),
            "金曜の午後に会議します。"
        )
        XCTAssertEqual(
            processor.cleanGeneratedOutput(korean, inputLanguage: .korean),
            "금요일 오후에 회의합니다."
        )
    }

    func testGeneratedOutputKeepsAnalysisTextWithoutFinalScaffold() {
        let processor = TextProcessor()
        let output = """
        Analysis:
        This heading is part of the requested text.
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(output, inputLanguage: .english),
            output
        )
    }

    func testTextFallbackPromptsDoNotClaimScreenImageIsAttached() {
        let processor = TextProcessor()
        let options = TextProcessingOptions(settings: AppSettings.shared, inputLanguage: .english)

        let formattingPrompt = processor.formattingSystemPrompt(
            options: options,
            screenContext: "OpenType settings",
            screenImageAvailable: false,
            memoryContext: "",
            inputContext: nil
        )
        let commandPrompt = processor.commandSystemPrompt(
            options: options,
            screenContext: "OpenType settings",
            screenImageAvailable: false,
            memoryContext: "",
            inputContext: nil
        )

        XCTAssertTrue(formattingPrompt.contains("OpenType settings"))
        XCTAssertTrue(commandPrompt.contains("OpenType settings"))
        XCTAssertFalse(formattingPrompt.contains("A screen image is attached"))
        XCTAssertFalse(commandPrompt.contains("A screen image is attached"))
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

    @MainActor
    func testFallbackNoticeSwitchesPersistedBackendToMLX() async {
        let suiteName = "TextProcessorFallbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.localLLMBackend = .espresso
        let pipeline = VoicePipeline(appState: AppState())
        await pipeline.textProcessor.espressoLLM.recordMLXFallback()

        let message = await pipeline.applyEspressoFallbackIfNeeded(settings: settings)

        XCTAssertEqual(settings.localLLMBackend, .mlx)
        XCTAssertEqual(defaults.string(forKey: "localLLMBackend"), LocalLLMBackend.mlx.rawValue)
        XCTAssertEqual(message, L("status.espresso_fell_back_to_mlx"))
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
        let output = try await processor.generateText(
            prompt: "Reply with exactly OK.",
            systemPrompt: "Return only the requested answer.",
            options: options,
            maxTokens: 8,
            temperature: 0
        )

        let fallbackMessage = await processor.consumeEspressoFallbackMessage()
        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotNil(fallbackMessage)
    }
}
