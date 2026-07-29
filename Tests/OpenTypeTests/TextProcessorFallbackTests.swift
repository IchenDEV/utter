import XCTest
@testable import OpenType

final class TextProcessorFallbackTests: XCTestCase {
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
}
