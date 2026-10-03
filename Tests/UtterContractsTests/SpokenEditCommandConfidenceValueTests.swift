import XCTest
@testable import UtterContracts

final class SpokenEditCommandConfidenceValueTests: XCTestCase {
    func testDecodesNestedPercentConfidenceAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":{"percent":91}}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":{"pct":"91"}}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesTopLevelPercentConfidenceAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence_percent":91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_selection","intent":null,"replacement":"new customer note","confidence_pct":"91%"}"#
            ),
            .replaceSelection("new customer note")
        )
    }

    func testTreatsPercentConfidenceAsMetadataInsideSemanticObjects() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: """
                {
                  "action": {"name": "rewrite_selection", "confidence_percent": 91},
                  "intent": {"preset": "meeting_notes", "confidencePercentage": "91%"},
                  "replacement": null,
                  "confidence": {"percentage": 91}
                }
                """
            ),
            .rewriteSelection(.meetingNotes)
        )
    }
}
