import XCTest
@testable import OpenType

final class RemoteLLMParsedPayloadTests: XCTestCase {
    func testParsesOpenAIContentObjectAsStructuredPayload() throws {
        let response = """
        {"choices":[{"message":{"content":{"final_text":"Ship the release notes today."}}}]}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIContentObjectCommandPayload() throws {
        let response = """
        {"choices":[{"message":{"content":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}}]}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIToolCallParametersObjectPayload() throws {
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
                      "parameters": {
                        "action": "replace_selection",
                        "intent": null,
                        "replacement": "send the customer update",
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
            .replaceSelection("send the customer update")
        )
    }

    func testParsesOpenAIToolCallParsedArgumentsPayload() throws {
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
                      "parsed_arguments": {
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

    func testPrefersOpenAIToolCallPayloadOverAssistantContent() throws {
        let response = #"""
        {"choices":[{"message":{"content":"I will update that now.","tool_calls":[{"type":"function","function":{"name":"emit_command","arguments":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}}]}}]}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIParsedMessageObject() throws {
        let response = """
        {"choices":[{"message":{"content":null,"parsed":{"final_text":"Ship the release notes today."}}}]}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIParsedCommandObject() throws {
        let response = """
        {"choices":[{"message":{"content":null,"parsed":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}}]}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIResponsesOutputParsedObject() throws {
        let response = """
        {"id":"resp_1","output_parsed":{"final_text":"今天下午同步发布计划。"}}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "今天下午同步发布计划。")
    }

    func testPrefersOpenAIResponsesOutputParsedOverOutputText() throws {
        let response = """
        {"id":"resp_1","output_text":"I will format that now.","output_parsed":{"final_text":"Ship the release notes today."}}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIResponsesOutputObjectPayload() throws {
        let response = """
        {"id":"resp_1","output":{"final_text":"今天下午同步发布计划。"}}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "今天下午同步发布计划。")
    }

    func testParsesOpenAIResponsesMessageParsedPayload() throws {
        let response = """
        {
          "id": "resp_1",
          "output": [
            {
              "type": "message",
              "content": [],
              "parsed": {
                "final_text": "Ship the release notes today."
              }
            }
          ]
        }
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testPrefersResponsesParsedPayloadOverMessageContent() throws {
        let response = #"""
        {"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"I will format that now."}],"parsed":{"final_text":"Ship the release notes today."}}]}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIResponsesMessageParsedCommandPayload() throws {
        let response = """
        {
          "id": "resp_1",
          "output": [
            {
              "type": "message",
              "content": [],
              "output_parsed": {
                "action": "replace_last",
                "intent": null,
                "replacement": "ship tomorrow",
                "confidence": 0.91
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

    func testParsesOpenAIResponsesArgsStringPayload() throws {
        let response = #"""
        {"id":"resp_1","output":[{"type":"function_call","name":"emit_final","args":"{\"final_text\":\"Ship the release notes today.\"}"}]}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testPrefersOpenAIResponsesFunctionCallPayloadOverMessageOutput() throws {
        let response = """
        {
          "id": "resp_1",
          "output": [
            {
              "type": "message",
              "content": [
                {"type": "output_text", "text": "I will update that now."}
              ]
            },
            {
              "type": "function_call",
              "name": "emit_command",
              "arguments": {
                "action": "replace_last",
                "intent": null,
                "replacement": "ship tomorrow",
                "confidence": 0.91
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

    func testPrefersOpenAIResponsesMessageToolCallsOverMessageContent() throws {
        let response = #"""
        {"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"I will update that now."}],"tool_calls":[{"type":"function","function":{"name":"emit_command","arguments":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}}]}]}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIResponsesArgumentsJSONPayload() throws {
        let response = #"""
        {"id":"resp_1","output":[{"type":"function_call","name":"emit_final","arguments_json":"{\"final_text\":\"今天下午同步发布计划。\"}"}]}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "今天下午同步发布计划。")
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }
}
