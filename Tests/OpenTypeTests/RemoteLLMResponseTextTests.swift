import XCTest
@testable import OpenType

final class RemoteLLMResponseTextTests: XCTestCase {
    func testParsesOpenAIStringContent() throws {
        let response = """
        {"choices":[{"message":{"content":"  Ship the release notes today.  "}}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAIContentBlocks() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": [
                  {"type":"text","text":"Ship the release notes."},
                  {"type":"image_url","image_url":{"url":"ignored"}},
                  {"type":"output_text","text":"Then confirm QA."}
                ]
              }
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes.\nThen confirm QA."
        )
    }

    func testParsesCaseInsensitiveEnvelopeKeys() throws {
        let openAIResponse = """
        {"Choices":[{"Message":{"Content":[{"Type":"output_text","Text":"Ship the release notes today."}]}}]}
        """
        let anthropicResponse = """
        {"Content":[{"Type":"text","Text":"今天下午同步发布计划。"}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(openAIResponse)),
            "Ship the release notes today."
        )
        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(anthropicResponse)),
            "今天下午同步发布计划。"
        )
    }

    func testParsesNestedOpenAITextBlock() throws {
        let response = """
        {"choices":[{"message":{"content":[{"type":"text","text":{"value":"今天下午同步发布计划。"}}]}}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "今天下午同步发布计划。"
        )
    }

    func testParsesLaterOpenAIChoiceWhenFirstChoiceHasNoText() throws {
        let response = """
        {
          "choices": [
            {"message":{"content":""}},
            {"message":{"content":[{"type":"text","text":"Ship the release notes today."}]}}
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testSkipsNonObjectOpenAIChoices() throws {
        let response = """
        {"choices":[null,"ignored",{"message":{"content":[{"type":"output_text","text":"Ship the release notes today."}]}}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAITextChoiceFallback() throws {
        let response = """
        {"choices":[{"text":"  Ship the release notes today.  "}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAIStreamingDeltaContent() throws {
        let response = #"""
        {"choices":[{"delta":{"content":"{\"final_text\":\"Ship the release notes today.\"}"}}]}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIStreamingDeltaToolCallArguments() throws {
        let response = #"""
        {
          "choices": [
            {
              "delta": {
                "tool_calls": [
                  {
                    "index": 0,
                    "type": "function",
                    "function": {
                      "name": "emit_command",
                      "arguments": {
                        "action": "replace_last",
                        "intent": null,
                        "replacement": "ship tomorrow",
                        "confidence": 0.91
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIResponsesOutputBlocks() throws {
        let response = """
        {
          "id": "resp_1",
          "output": [
            {
              "type": "message",
              "content": [
                {"type":"output_text","text":"Ship the release notes."},
                {"type":"image_url","image_url":{"url":"ignored"}},
                {"type":"output_text","text":"Then confirm QA."}
              ]
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes.\nThen confirm QA."
        )
    }

    func testParsesOpenAIResponsesOutputTextShortcut() throws {
        let response = """
        {"id":"resp_1","output_text":"  今天下午同步发布计划。  "}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "今天下午同步发布计划。"
        )
    }

    func testParsesOpenAIChatToolCallArguments() throws {
        let response = #"""
        {
          "choices": [
            {
              "message": {
                "content": null,
                "tool_calls": [
                  {
                    "type": "function",
                    "function": {
                      "name": "emit_final",
                      "arguments": "{\"final_text\":\"Ship the release notes today.\"}"
                    }
                  }
                ]
              }
            }
          ]
        }
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIResponsesFunctionCallArguments() throws {
        let response = #"""
        {
          "id": "resp_1",
          "output": [
            {
              "type": "function_call",
              "name": "emit_final",
              "arguments": "{\"final_text\":\"今天下午同步发布计划。\"}"
            }
          ]
        }
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "今天下午同步发布计划。")
    }

    func testParsesDecodedToolCallArgumentObject() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": null,
                "tool_calls": [
                  {
                    "type": "function",
                    "function": {
                      "name": "emit_final",
                      "arguments": {"final_text": "Ship the release notes today."}
                    }
                  }
                ]
              }
            }
          ]
        }
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesDecodedToolCallCommandObject() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": null,
                "tool_calls": [
                  {
                    "type": "function",
                    "function": {
                      "name": "emit_command",
                      "arguments": {
                        "action": "replace_last",
                        "intent": null,
                        "replacement": "ship tomorrow",
                        "confidence": 0.91
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesAllAnthropicTextBlocks() throws {
        let response = """
        {
          "content": [
            {"type":"thinking","thinking":"internal reasoning"},
            {"type":"text","text":"Ship the release notes."},
            {"type":"tool_use","name":"ignored"},
            {"type":"text","text":"Then confirm QA."}
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(response)),
            "Ship the release notes.\nThen confirm QA."
        )
    }

    func testParsesAnthropicToolUseInputObjects() throws {
        let finalResponse = #"{"content":[{"type":"tool_use","name":"emit_final","input":{"final_text":"Ship the release notes today."}}]}"#
        let finalRaw = try RemoteLLMResponseText.anthropic(from: data(finalResponse))

        XCTAssertEqual(finalRaw, "Ship the release notes today.")

        let commandResponse = #"{"content":[{"type":"tool_use","name":"emit_command","input":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}]}"#
        let commandRaw = try RemoteLLMResponseText.anthropic(from: data(commandResponse))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: commandRaw),
            .replaceLast("ship tomorrow")
        )
    }

    func testRejectsResponsesWithoutText() {
        XCTAssertThrowsError(
            try RemoteLLMResponseText.openAI(from: data(#"{"choices":[{"message":{"content":[]}}]}"#))
        )
        XCTAssertThrowsError(
            try RemoteLLMResponseText.anthropic(from: data(#"{"content":[{"type":"thinking","thinking":"no text"}]}"#))
        )
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }
}
