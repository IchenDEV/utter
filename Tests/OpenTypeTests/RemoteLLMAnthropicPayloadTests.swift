import XCTest
@testable import OpenType

final class RemoteLLMAnthropicPayloadTests: XCTestCase {
    func testParsesAnthropicNonArrayContent() throws {
        let stringResponse = #"{"content":"  Ship the release notes today.  "}"#
        let objectResponse = #"{"content":{"type":"text","text":"今天下午同步发布计划。"}}"#

        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(stringResponse)),
            "Ship the release notes today."
        )
        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(objectResponse)),
            "今天下午同步发布计划。"
        )
    }

    func testParsesAnthropicToolPayloadObject() throws {
        let response = """
        {
          "content": [
            {
              "type": "tool_use",
              "name": "emit_command",
              "payload": {
                "action": "rewrite_selection",
                "intent": "summary",
                "replacement": null,
                "confidence": 0.91
              }
            }
          ]
        }
        """

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .rewriteSelection(.summary)
        )
    }

    func testPrefersAnthropicToolUseFinalPayloadOverTextBlocks() throws {
        let response = """
        {
          "content": [
            {"type": "text", "text": "I will format that now."},
            {
              "type": "tool_use",
              "name": "emit_final",
              "input": {
                "final_text": "Ship the release notes today."
              }
            }
          ]
        }
        """

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testPrefersAnthropicToolUseCommandPayloadOverTextBlocks() throws {
        let response = """
        {
          "content": [
            {"type": "text", "text": "I will update that now."},
            {
              "type": "tool_use",
              "name": "emit_command",
              "input": {
                "action": "replace_last",
                "intent": null,
                "replacement": "ship tomorrow",
                "confidence": 0.91
              }
            }
          ]
        }
        """

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }
}
