import XCTest
@testable import OpenType

/// Structured payload extraction lives at the remote-API boundary
/// (`LLMFinalTextOutput` via `RemoteLLMResponseText`), not in the text cleaner.
final class StructuredFinalTextDecodingTests: XCTestCase {
    func testExtractsDoubleEncodedStructuredFinalTextJSON() {
        let payload = #"""
        {"final_text":"{\"final_text\":\"Ship the release notes today.\"}","explanation":"adapter returned JSON as a string"}
        """#

        XCTAssertEqual(
            LLMFinalTextOutput.text(from: payload),
            "Ship the release notes today."
        )
    }

    func testExtractsFencedJSONInsideStructuredFinalText() {
        let payload = #"""
        {"payload":{"output_text":"```json\n{\"final_text\":\"今天下午同步发布计划。\"}\n```"}}
        """#

        XCTAssertEqual(
            LLMFinalTextOutput.text(from: payload),
            "今天下午同步发布计划。"
        )
    }

    func testKeepsLiteralJSONInsideStructuredFinalTextWhenItHasNoFinalPayload() {
        let payload = #"""
        {"final_text":"{\"name\":\"OpenType\",\"mode\":\"voice\"}","explanation":"user asked for JSON"}
        """#

        XCTAssertEqual(
            LLMFinalTextOutput.text(from: payload),
            #"{"name":"OpenType","mode":"voice"}"#
        )
    }

    func testExtractsToolCallArgumentsObjectFinalText() {
        let payload = #"""
        {"tool_call":{"function":{"name":"emit_final","arguments":{"final_text":"Ship the release notes today."}}}}
        """#

        XCTAssertEqual(
            LLMFinalTextOutput.text(from: payload),
            "Ship the release notes today."
        )
    }

    func testExtractsToolUseInputFinalText() {
        let payload = #"""
        {"type":"tool_use","name":"emit_final","input":{"final_text":"今天下午同步发布计划。"}}
        """#

        XCTAssertEqual(
            LLMFinalTextOutput.text(from: payload),
            "今天下午同步发布计划。"
        )
    }

    func testExtractsParsedWrapperFinalText() {
        let payload = #"""
        {"parsed":{"final_text":"Ship the release notes today."}}
        """#

        XCTAssertEqual(
            LLMFinalTextOutput.text(from: payload),
            "Ship the release notes today."
        )
    }

    func testReturnsNilForToolArgumentsJSONWithoutFinalPayload() {
        let payload = #"""
        {"tool_call":{"arguments":"{\"name\":\"OpenType\",\"mode\":\"voice\"}"}}
        """#

        XCTAssertNil(LLMFinalTextOutput.text(from: payload))
    }
}
