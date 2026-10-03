import UtterContracts
import XCTest
@testable import UtterRemoteInference

final class RemoteLLMAnthropicEventStreamAliasTests: XCTestCase {
    func testParsesCamelCaseToolInputDeltas() throws {
        let response = #"""
        event: content_block_start
        data: {"type":"content_block_start","index":0,"contentBlock":{"type":"tool_use","id":"toolu_1","name":"emit_command","inputJson":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partialJson":"\"action\":\"replace_last\",\"intent\":null,"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partialJson":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}
        """#

        let rawText = try RemoteLLMResponseText.anthropic(from: Data(response.utf8))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesCamelCaseContentBlockIndexTextDeltas() throws {
        let response = #"""
        event: content_block_start
        data: {"type":"content_block_start","contentBlockIndex":0,"contentBlock":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","contentBlockIndex":0,"delta":{"type":"text_delta","text":"Ship the "}}

        event: content_block_delta
        data: {"type":"content_block_delta","contentBlockIndex":0,"delta":{"type":"text_delta","text":"release notes today."}}
        """#

        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: Data(response.utf8)),
            "Ship the release notes today."
        )
    }

    func testParsesSingleBlockToolInputDeltasWithoutIndex() throws {
        let response = #"""
        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partialJson":"\"action\":\"replace_last\",\"intent\":null,"}}

        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partialJson":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91"}}
        """#

        let rawText = try RemoteLLMResponseText.anthropic(from: Data(response.utf8))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }
}
