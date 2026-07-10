import XCTest
@testable import OpenType

/// `LLMFinalTextOutput.wholeJSONText` powers the remote-API boundary: it only
/// resolves payloads that are entirely one structured value. Mixed text is
/// never mined — that is asserted via `FormattedOutputCleaner`.
final class LLMFinalTextOutputTests: XCTestCase {
    func testKeepsLabeledOutputTextArrayAfterPreamble() {
        // Text with an embedded JSON tail is a text reply, not a structured
        // payload; it must survive verbatim.
        let llmOutput = """
        Final response:
        [{"type":"output_text","text":"Ship the release notes."},{"type":"output_text","text":"Then confirm QA."}]
        """

        XCTAssertNil(LLMFinalTextOutput.wholeJSONText(from: llmOutput))
        XCTAssertEqual(FormattedOutputCleaner.clean(llmOutput), llmOutput)
    }

    func testKeepsOrdinaryEmbeddedArrayWithoutExplicitFinalText() {
        let llmOutput = #"The payload is [{"text":"Ship the release notes today.","mode":"voice"}]."#

        XCTAssertNil(LLMFinalTextOutput.wholeJSONText(from: llmOutput))
        XCTAssertEqual(FormattedOutputCleaner.clean(llmOutput), llmOutput)
    }

    func testDoesNotMineEmbeddedExplicitFinalText() {
        let llmOutput = #"Document this example: {"final_text":"hello"}."#

        XCTAssertNil(LLMFinalTextOutput.text(from: llmOutput))
    }

    func testExtractsTopLevelTextBlockArray() {
        let llmOutput = """
        [{"type":"text","text":"Ship the release notes."},{"type":"text","text":"Then confirm QA."}]
        """

        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
        )
    }

    func testExtractsTypedFinalTextContentPayload() {
        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: #"{"type":"final_text","content":"Ship the release notes today."}"#),
            "Ship the release notes today."
        )
    }

    func testExtractsCamelAndKebabTypedFinalTextPayloads() {
        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: #"{"type":"finalText","content":"Ship the release notes today."}"#),
            "Ship the release notes today."
        )
        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: #"{"type":"formatted-text","value":"今天下午同步发布计划。"}"#),
            "今天下午同步发布计划。"
        )
    }

    func testExtractsValueEnvelopeInsideTypedFinalText() {
        let llmOutput = """
        {"type":"output_text","text":{"value":"Ship the release notes today.","annotations":[]}}
        """

        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: llmOutput),
            "Ship the release notes today."
        )
    }

    func testExtractsOpenAIChatTextBlocksFromWholeResponse() {
        let llmOutput = """
        {"choices":[{"message":{"content":[{"type":"text","text":"Ship the release notes."},{"type":"text","text":"Then confirm QA."}]}}]}
        """

        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
        )
    }

    func testExtractsOpenAIDeltaFinalTextFromWholeResponse() {
        let llmOutput = #"""
        {"choices":[{"delta":{"content":"{\"final_text\":\"Ship the release notes today.\"}"}}]}
        """#

        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: llmOutput),
            "Ship the release notes today."
        )
    }

    func testReturnsNilForPlainTextDeltaEnvelope() {
        // A plain-text delta carries no structured final value, so there is
        // nothing to resolve — envelope parsing happens before this layer.
        let llmOutput = #"{"choices":[{"delta":{"content":"Ship the release notes today."}}]}"#

        XCTAssertNil(LLMFinalTextOutput.wholeJSONText(from: llmOutput))
    }

    func testExtractsResponsesTextBlocksFromWholeResponse() {
        let llmOutput = """
        {"id":"resp_1","output":[{"type":"message","content":[{"type":"text","text":"今天下午同步发布计划。"}]}]}
        """

        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: llmOutput),
            "今天下午同步发布计划。"
        )
    }

    func testExtractsAnthropicTextBlocksFromWholeResponse() {
        let llmOutput = """
        {"content":[{"type":"thinking","thinking":"internal reasoning"},{"type":"text","text":"Ship the release notes."},{"type":"text","text":"Then confirm QA."}]}
        """

        XCTAssertEqual(
            LLMFinalTextOutput.wholeJSONText(from: llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
        )
    }

    func testReturnsNilForOrdinaryTopLevelArrayWithoutResponseMetadata() {
        XCTAssertNil(
            LLMFinalTextOutput.wholeJSONText(from: #"[{"text":"Ship the release notes today.","mode":"voice"}]"#)
        )
    }

    func testReturnsNilForOrdinaryOutputStringJSON() {
        XCTAssertNil(
            LLMFinalTextOutput.wholeJSONText(from: #"{"output":"Ship the release notes today.","mode":"voice"}"#)
        )
    }

    func testReturnsNilForOrdinaryContentArrayJSON() {
        XCTAssertNil(
            LLMFinalTextOutput.wholeJSONText(from: #"{"content":[{"text":"Ship the release notes today.","mode":"voice"}],"mode":"voice"}"#)
        )
    }
}
