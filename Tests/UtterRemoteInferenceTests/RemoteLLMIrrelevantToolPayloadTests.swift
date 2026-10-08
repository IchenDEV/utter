import UtterContracts
import XCTest
@testable import UtterRemoteInference

final class RemoteLLMIrrelevantToolPayloadTests: XCTestCase {
    func testOpenAIChatFallsBackToTextWhenToolPayloadIsNotOutput() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": "Ship the release notes today.",
                "tool_calls": [
                  {
                    "type": "function",
                    "function": {
                      "name": "lookup_context",
                      "arguments": {
                        "query": "release notes"
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testOpenAIResponsesFallsBackToMessageWhenFunctionCallIsNotOutput() throws {
        let response = """
        {
          "id": "resp_1",
          "output": [
            {
              "type": "message",
              "content": [
                {"type": "output_text", "text": "Ship the release notes today."}
              ]
            },
            {
              "type": "function_call",
              "name": "lookup_context",
              "arguments": {
                "query": "release notes"
              }
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testOpenAIIgnoresUntypedMetadataObjectsInContentBlocks() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": [
                  {"query": "release notes", "source": "retrieval"},
                  {"type": "output_text", "text": "Ship the release notes today."}
                ]
              }
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testAnthropicFallsBackToTextWhenToolPayloadIsNotOutput() throws {
        let response = """
        {
          "content": [
            {"type": "text", "text": "Ship the release notes today."},
            {
              "type": "tool_use",
              "name": "lookup_context",
              "input": {
                "query": "release notes"
              }
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(response)),
            "Ship the release notes today."
        )
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }
}
