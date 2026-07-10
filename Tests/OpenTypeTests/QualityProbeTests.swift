import XCTest
@testable import OpenType

/// End-to-end regression cases distilled from previously observed failures.
final class QualityProbeTests: XCTestCase {
    // MARK: - A. Streaming preview merge (sliding window boundary)

    func testProbe_streamingMerge_windowRepeatsPrefix() {
        let acc = StreamingPreviewAccumulator()
        _ = acc.merge("可能会有两")
        let merged = acc.merge("可能会有这种意外的泄露")
        XCTAssertEqual(merged, "可能会有这种意外的泄露")
    }

    func testProbe_streamingMerge_punctuationCollision() {
        // Window 1 tentatively closes with “。”, window 2 re-hears the same
        // boundary with “，”.
        let acc = StreamingPreviewAccumulator()
        _ = acc.merge("我们先发布。")
        let merged = acc.merge("先发布，然后再回归")
        XCTAssertEqual(merged, "我们先发布，然后再回归")
    }

    func testProbe_streamingMerge_shortCJKOverlapFalsePositive() {
        // 2-character CJK overlap is enough to trigger a fuzzy merge; verify a
        // legitimate repetition is not wrongly deduplicated.
        let acc = StreamingPreviewAccumulator()
        _ = acc.merge("测试测试")
        let merged = acc.merge("测试通过了")
        XCTAssertEqual(merged, "测试测试通过了")
    }

    func testProbe_streamingMerge_retractedCharacterLocksIn() {
        let acc = StreamingPreviewAccumulator()
        _ = acc.merge("下面这段话整理后")
        _ = acc.merge("下面这段话整理后是什么")
        let merged = acc.merge("整理后是什么可能会有")
        XCTAssertEqual(merged, "下面这段话整理后是什么可能会有")
    }

    // MARK: - B. Repeated transcript collapse (intentional repetition)

    func testProbe_sanitizer_intentionalRepetitionPreserved() {
        var strongAudio = AudioCaptureActivity()
        strongAudio.record(rms: 0.02, frameCount: 16_000)
        let prepared = TranscriptionSanitizer.prepare("这个方案可以这个方案可以", audioActivity: strongAudio)
        XCTAssertEqual(prepared, "这个方案可以这个方案可以")
    }

    func testProbe_sanitizer_emphasisRepetitionThreeTimes() {
        var strongAudio = AudioCaptureActivity()
        strongAudio.record(rms: 0.02, frameCount: 16_000)
        let prepared = TranscriptionSanitizer.prepare("非常重要非常重要非常重要", audioActivity: strongAudio)
        XCTAssertEqual(prepared, "非常重要非常重要非常重要")
    }

    // MARK: - C. Output cleaner must keep legit content

    func testProbe_cleaner_legitExplanationLineKept() {
        let input = "更新了配置文件。\n说明：新增了两个字段。"
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, input)
    }

    func testProbe_cleaner_legitNotesLineKept() {
        let input = "Deploy finished.\nNotes: rollback window is 30 minutes."
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, input)
    }

    func testProbe_scaffold_analysisAnswerContentKept() {
        let processor = TextProcessor()
        let input = "分析：市场规模很大。\n答案：值得做。"
        let output = processor.cleanGeneratedOutput(input, inputLanguage: .chinese)
        XCTAssertEqual(output, input)
    }

    func testProbe_cleaner_dictatedJSONKept() {
        let input = #"{"text": "hello", "confidence": 0.9}"#
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, input)
    }

    func testProbe_cleaner_dictatedJSONWithFinalTextKeyKept() {
        let input = #"请把 {"final_text": "你好"} 这个例子记录一下"#
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, input)
    }

    func testProbe_cleaner_codeFenceContentUnwrapped() {
        let input = "```swift\nlet a = 1\n```"
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, "let a = 1")
    }

    // MARK: - D. Local ASR runner output parsing

    func testProbe_localASR_responseLinesNeverConcatenate() {
        // Regression guard: the old multi-line joiner produced
        // "可能会有两可能会有这种意外的泄露" by gluing partial lines together.
        // The serve protocol parses each line independently.
        let first = LocalASRServerResponse.parse(line: #"{"text": "可能会有两"}"#)
        let second = LocalASRServerResponse.parse(line: #"{"text": "可能会有这种意外的泄露"}"#)
        XCTAssertEqual(first, .text("可能会有两"))
        XCTAssertEqual(second, .text("可能会有这种意外的泄露"))
    }

    // MARK: - E. Direct-mode whitespace handling
    // (see testProbe_basicClean_preservesNewlines below)

    // MARK: - F. Prompt text block must embed user content verbatim

    func testProbe_promptBlock_keepsDictatedDelimiters() {
        let block = PromptTextBlock.block("代码里写的是 <<<EOF 和 >>> 结束符")
        XCTAssertTrue(block.contains("代码里写的是 <<<EOF 和 >>> 结束符"))
    }

    // MARK: - G. Small-model echo / wrapper leaks that the cleaner must strip

    func testProbe_cleaner_tripleAngleWrapperStripped() {
        // Small models often mimic the <<< >>> input delimiters around output.
        let input = "<<<\n我们周五下午开会。\n>>>"
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, "我们周五下午开会。")
    }

    func testProbe_cleaner_inlineLabelVariantStripped() {
        let input = "整理后的文本是：我们周五下午开会。"
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, "我们周五下午开会。")
    }

    func testProbe_cleaner_prefixedAnswerSentenceStripped() {
        let input = "好的，以下是整理后的文本：我们周五下午开会。"
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, "我们周五下午开会。")
    }

    func testProbe_cleaner_echoedQuestionAnswerStripped() {
        let input = "下面这段话整理后是：我们周五下午开会。"
        let cleaned = FormattedOutputCleaner.clean(input)
        XCTAssertEqual(cleaned, "我们周五下午开会。")
    }

    func testProbe_scaffold_qwenThinkTagUnclosedLeak() {
        let processor = TextProcessor()
        let input = "<think>\n\n</think>\n\n我们周五下午开会。"
        let output = processor.cleanGeneratedOutput(input, inputLanguage: .chinese)
        XCTAssertEqual(output, "我们周五下午开会。")
    }

    // MARK: - H. Sanitizer vs verbatim mode

    func testProbe_sanitizer_verbatimDoubleRepeatPreserved() {
        let prepared = TranscriptionSanitizer.prepare("这个方案可以这个方案可以")
        XCTAssertEqual(prepared, "这个方案可以这个方案可以")
    }

    // MARK: - I. Direct-mode newline preservation

    func testProbe_basicClean_preservesNewlines() {
        let processor = TextProcessor()
        let cleaned = processor.basicClean(text: "第一行\n第二行\n第三行")
        XCTAssertEqual(cleaned, "第一行\n第二行\n第三行")
    }
}
