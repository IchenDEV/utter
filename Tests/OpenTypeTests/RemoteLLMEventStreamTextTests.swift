import XCTest
@testable import OpenType

final class RemoteLLMEventStreamTextTests: XCTestCase {
    func testParsesOpenAIEventStreamContentDeltas() throws {
        let response = #"""
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"{\"final_text\":\"Ship "}}]}

        data: {"choices":[{"delta":{"content":"the release notes today.\"}"}}]}

        data: [DONE]
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIEventStreamToolArgumentDeltas() throws {
        let response = #"""
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"name":"emit_command","arguments":"{\"action\":\"replace_last\",\"intent\":null,"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}}]}}]}

        data: [DONE]
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIEventStreamDecodedToolArgumentObject() throws {
        let response = """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"name":"emit_command","arguments":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}}]}}]}

        data: [DONE]
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIEventStreamSingularToolCallObject() throws {
        let response = """
        data: {"choices":[{"delta":{"tool_call":{"type":"function","function":{"name":"emit_command","arguments":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}}}}]}

        data: [DONE]
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIEventStreamPlainTextDeltas() throws {
        let response = """
        event: message
        data: {"choices":[{"delta":{"content":"Ship the "}}]}

        data: {"choices":[{"delta":{"content":"release notes today."}}]}

        data: [DONE]
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAINDJSONContentDeltas() throws {
        let response = #"""
        {"choices":[{"delta":{"content":"{\"final_text\":\"Ship "}}]}
        {"choices":[{"delta":{"content":"the release notes today.\"}"}}]}
        {"done":true}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIEventStreamContentBlockDeltas() throws {
        let response = #"""
        data: {"choices":[{"delta":{"content":[{"type":"output_text","text":"{\"final_text\":\"Ship "}]}}]}

        data: {"choices":[{"delta":{"content":{"type":"output_text","text":"the release notes today.\"}"}}}]}

        data: [DONE]
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testRejectsEmptyOpenAIEventStream() {
        XCTAssertThrowsError(
            try RemoteLLMResponseText.openAI(from: data("data: [DONE]\n\n"))
        )
    }

    func testParsesOpenAIResponsesEventStreamTextDeltas() throws {
        let response = #"""
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"{\"final_text\":\"Ship "}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"the release notes today.\"}"}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_1"}}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIResponsesFunctionArgumentDeltas() throws {
        let response = #"""
        data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"delta":"{\"action\":\"replace_last\",\"intent\":null,"}

        data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"delta":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}

        data: {"type":"response.function_call_arguments.done","item_id":"fc_1","output_index":0,"arguments":"{\"action\":\"replace_last\",\"intent\":null,\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIResponsesFunctionArgumentObjectDone() throws {
        let response = """
        data: {"type":"response.function_call_arguments.done","item_id":"fc_1","output_index":0,"arguments":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIResponsesCompletedOutputItem() throws {
        let response = #"""
        data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","arguments":"{\"final_text\":\"Ship the release notes today.\"}"}}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesOpenAIResponsesCompletedResponseOutput() throws {
        let response = """
        data: {"type":"response.completed","response":{"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"Ship the release notes today."}]}]}}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAIResponsesContentPartDone() throws {
        let response = """
        data: {"type":"response.content_part.done","item_id":"msg_1","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Ship the release notes today."}}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAIResponsesNDJSONTextDeltas() throws {
        let response = #"""
        {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"{\"final_text\":\"Ship "}
        {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"the release notes today.\"}"}
        {"type":"response.completed","response":{"id":"resp_1"}}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesAnthropicEventStreamTextDeltas() throws {
        let response = #"""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"final_text\":\"Ship "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"the release notes today.\"}"}}

        event: message_stop
        data: {"type":"message_stop"}
        """#

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesAnthropicEventStreamToolInputDeltas() throws {
        let response = #"""
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"emit_command","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"action\":\"replace_last\",\"intent\":null,"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}
        """#

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesAnthropicEventStreamPlainTextDeltas() throws {
        let response = """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Ship the "}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"release notes today."}}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesAnthropicNDJSONTextDeltas() throws {
        let response = #"""
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"final_text\":\"Ship "}}
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"the release notes today.\"}"}}
        {"type":"message_stop"}
        """#

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    private func data(_ text: String) -> Data {
        Data(text.utf8)
    }
}
