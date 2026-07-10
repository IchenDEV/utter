import XCTest
@testable import OpenType

final class RemoteLLMOpenAIEventStreamAliasTests: XCTestCase {
    func testParsesTypedContentDeltaBlocks() throws {
        let response = #"""
        data: {"choices":[{"delta":{"content":[{"type":"output_text_delta","delta":"{\"final_text\":\"Ship "}]}}]}

        data: {"choices":[{"delta":{"content":{"type":"output_text_delta","delta":"the release notes today.\"}"}}}]}

        data: [DONE]
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: Data(response.utf8))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesTypedTextDeltaBlocksWithTextAlias() throws {
        let response = #"""
        data: {"choices":[{"delta":{"content":{"type":"text_delta","text":"Ship the "}}}]}

        data: {"choices":[{"delta":{"content":{"type":"text_delta","text":"release notes today."}}}]}

        data: [DONE]
        """#

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: Data(response.utf8)),
            "Ship the release notes today."
        )
    }

    func testParsesResponsesEventNameWhenPayloadOmitsType() throws {
        let response = #"""
        event: response.output_text.delta
        data: {"item_id":"msg_1","output_index":0,"content_index":0,"delta":"{\"final_text\":\"Ship "}

        event: response.output_text.delta
        data: {"item_id":"msg_1","output_index":0,"content_index":0,"delta":"the release notes today.\"}"}

        event: response.completed
        data: {"response":{"id":"resp_1"}}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: Data(response.utf8))

        XCTAssertEqual(rawText, "Ship the release notes today.")
    }

    func testParsesResponsesFunctionArgumentsWhenPayloadOmitsType() throws {
        let response = #"""
        event: response.function_call_arguments.delta
        data: {"item_id":"fc_1","output_index":0,"delta":"{\"action\":\"replace_last\",\"intent\":null,"}

        event: response.function_call_arguments.delta
        data: {"item_id":"fc_1","output_index":0,"delta":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}

        event: response.function_call_arguments.done
        data: {"item_id":"fc_1","output_index":0,"arguments":"{\"action\":\"replace_last\",\"intent\":null,\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: Data(response.utf8))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }
}
