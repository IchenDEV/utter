import XCTest
@testable import UtterContracts

final class SpokenEditCommandActionValueTests: XCTestCase {
    func testDecodesTopLevelCommandTypeActionAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"command_type":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"operationType":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesStructuredCommandTypeActionAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"command_type":"replace_selection","reason":"final command"},"intent":null,"replacement":"new customer note","confidence":0.91}"#
            ),
            .replaceSelection("new customer note")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"operationType":"rewrite_last","confidence":0.91},"intent":"formal","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.formal)
        )
    }

    func testDecodesStructuredActionTargetPairs() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace","target":"last_insertion","intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"operation":"rewrite","scope":{"type":"selection"},"intent":"meeting_notes","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"delete","object":"selected_text","intent":null,"replacement":null,"confidence":0.91}"#
            ),
            .deleteSelection
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"command":"undo","edit_target":"previous_insertion","intent":null,"replacement":null,"confidence":0.91}"#
            ),
            .undoLastInsertion
        )
    }

    func testDecodesStructuredTargetObjects() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite","target":{"kind":"selection","reason":"selected text"},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace","scope":{"entity":"lastInsertion","confidence":0.91},"intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesBooleanTargetFlagObjects() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite","target":{"selection":true,"reason":"selected text"},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace","target":{"lastInsertion":true,"selection":false},"intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesBooleanActionFlagObjects() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"rewrite":true,"reason":"model selected rewrite"},"target":{"selection":true},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"replaceLast":true,"confidence":0.91},"intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesTargetsNestedInsideActionObjects() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"type":"rewrite","target":{"kind":"selection"}},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"replace":true,"scope":{"entity":"lastInsertion"}},"intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesActionParameterTargetContainers() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"name":"rewrite","parameters":{"target":{"kind":"selection"}}},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"operation":"replace","args":{"scope":{"entity":"lastInsertion"}}},"intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }
}
