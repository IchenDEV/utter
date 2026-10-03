import XCTest
@testable import UtterContracts

final class SpokenEditCommandMetadataValueTests: XCTestCase {
    func testDecodesActionObjectWithDescriptionMetadata() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: """
                {
                  "action": {
                    "name": "rewrite_selection",
                    "description": "safe edit action chosen by the model"
                  },
                  "intent": "summary",
                  "replacement": null,
                  "confidence": 0.91
                }
                """
            ),
            .rewriteSelection(.summary)
        )
    }

    func testDecodesIntentObjectWithExplanationMetadata() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: """
                {
                  "action": "rewrite_last",
                  "intent": {
                    "preset": "meeting_notes",
                    "explanation": "the user asked to turn the text into notes"
                  },
                  "replacement": null,
                  "confidence": 0.91
                }
                """
            ),
            .rewriteLast(.meetingNotes)
        )
    }

    func testDecodesReplacementObjectWithDescriptionMetadata() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: """
                {
                  "action": "replace_last",
                  "intent": null,
                  "replacement": {
                    "text": "ship tomorrow at 3 PM",
                    "description": "replacement text only"
                  },
                  "confidence": 0.91
                }
                """
            ),
            .replaceLast("ship tomorrow at 3 PM")
        )
    }

    func testDecodesCertaintyAsSemanticObjectMetadata() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"name":"rewrite_selection","certainty":0.91},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite","target":{"kind":"selection","certainty":0.91},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":{"preset":"meeting_notes","certainty":0.91},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.meetingNotes)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"text":"ship tomorrow at 3 PM","certainty":0.91},"confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow at 3 PM")
        )
    }

    func testDecodesJustificationAsSemanticObjectMetadata() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"name":"rewrite_selection","justification":"best action"},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite","target":{"kind":"selection","justification":"selected text"},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":{"preset":"meeting_notes","justification":"meeting transcript"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.meetingNotes)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"text":"ship tomorrow at 3 PM","justification":"corrected date"},"confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow at 3 PM")
        )
    }
}
