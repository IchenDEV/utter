import XCTest
@testable import OpenType

final class RemoteLLMJSONBlockTests: XCTestCase {
    func testParsesOpenAIJSONContentBlockAsFinalText() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": [
                  {
                    "type": "json",
                    "json": {
                      "final_text": "Ship the release notes today."
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

    func testParsesOpenAIJSONContentBlockAsCommand() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": [
                  {
                    "type": "output_json",
                    "json": {
                      "action": "replace_last",
                      "intent": null,
                      "replacement": "ship tomorrow",
                      "confidence": 0.91
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

    func testParsesAnthropicJSONContentBlockAsFinalText() throws {
        let response = """
        {
          "content": [
            {
              "type": "json",
              "json": {
                "final_text": "今天下午同步发布计划。"
              }
            }
          ]
        }
        """

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(rawText, "今天下午同步发布计划。")
    }

    func testParsesTypedFinalTextContentBlocks() throws {
        let openAIResponse = """
        {"choices":[{"message":{"content":[{"type":"final_text","content":"Ship the release notes today."}]}}]}
        """
        let anthropicResponse = """
        {"content":[{"type":"formatted_text","value":"今天下午同步发布计划。"}]}
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

    func testParsesNormalizedBlockTypeVariants() throws {
        let openAIResponse = """
        {"choices":[{"message":{"content":[{"type":"outputText","text":"Ship the release notes today."}]}}]}
        """
        let anthropicResponse = """
        {"content":[{"type":"final-text","value":"今天下午同步发布计划。"}]}
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

    func testParsesCaseInsensitiveContentBlockKeys() throws {
        let openAIResponse = """
        {"choices":[{"message":{"content":[{"Type":"output_text","Text":"Ship the release notes today."}]}}]}
        """
        let anthropicResponse = """
        {"content":[{"Type":"final_text","Value":"今天下午同步发布计划。"}]}
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

    func testIgnoresIrrelevantJSONContentBlockAndFallsBackToText() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": [
                  {"type": "json", "json": {"query": "release notes"}},
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

    func testResolvesFinalTextFromWholeJSONContentEnvelope() throws {
        // A whole-message JSON envelope is resolved at the API boundary, not by
        // the text cleaner.
        let response = """
        {"content":[{"type":"json","json":{"final_text":"Ship the release notes today."}}]}
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
