import XCTest
@testable import UtterContracts

final class SpokenEditCommandLLMRobustnessTests: XCTestCase {
    func testSkipsLeadingNonResolutionJSONObject() {
        let output = """
        Example payload:
        {"ignored":true}

        Final:
        {"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.91}
        """

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .rewriteSelection(.summary)
        )
    }

    func testPrefersLaterCommandOverLeadingNoneCandidate() {
        let output = """
        Preliminary:
        {"action":"none","intent":null,"replacement":null,"confidence":0}

        Final:
        {"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.91}
        """

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .rewriteSelection(.summary)
        )
    }

    func testPrefersLaterCommandOverLeadingLowConfidenceCandidate() {
        let output = """
        Earlier candidate:
        {"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.62}

        Final:
        {"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}
        """

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesResolutionNestedInWrapperObject() {
        let output = """
        Final result:
        {
          "result": {
            "action": "rewrite_selection",
            "intent": "summary",
            "replacement": null,
            "confidence": 0.91
          }
        }
        """

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .rewriteSelection(.summary)
        )
    }

    func testDecodesResolutionFromJSONStringArguments() {
        let output = #"""
        {"tool_call":{"arguments":"{\"action\":\"replace_last\",\"intent\":null,\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}}
        """#

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesSingleValueObjectIntentAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"Preset":"meeting_notes"},"replacement":null,"confidence":{"Score":0.92}}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
    }

    func testDecodesPresetIntentWithMetadataAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"preset":"summary","reason":"best fitting edit preset"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"type":"preset","value":"meeting_notes"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
    }

    func testDecodesCustomInstructionObjectWithMetadata() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"type":"custom","instruction":"make this warmer for a customer","reason":"contains extra tone"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.custom("make this warmer for a customer"))
        )
    }

    func testDecodesCaseInsensitiveTopLevelResolutionFields() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"Action":"Replace_Last","Intent":null,"Replacement":{"Text":"ship tomorrow"},"Confidence":{"Score":0.92}}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesStructuredActionValues() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"action":"rewrite_selection","reason":"final answer"},"intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"type":"replace_last","confidence":0.91},"intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesTopLevelActionAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"command":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"operation":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesTopLevelIntentAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","preset":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","instruction":"make it warmer for a customer","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.custom("make it warmer for a customer"))
        )
    }

    func testDecodesTopLevelReplacementAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"text":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_selection","intent":null,"new_text":"new customer note","confidence":0.91}"#
            ),
            .replaceSelection("new customer note")
        )
    }

    func testDecodesStructuredIntentDetailsAsCustomInstruction() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: """
                {
                  "action": "rewrite_selection",
                  "intent": {
                    "audience": "customer",
                    "task": "turn this into an apology with one concrete next step",
                    "tone": "warm"
                  },
                  "replacement": null,
                  "confidence": {"value": "93%"}
                }
                """
            ),
            .rewriteSelection(.custom("audience: customer; task: turn this into an apology with one concrete next step; tone: warm"))
        )
    }

    func testDecodesStructuredReplacementText() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"text":"ship tomorrow at 3 PM"},"confidence":{"confidence":0.9}}"#
            ),
            .replaceLast("ship tomorrow at 3 PM")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"old":"ship today","new":"ship tomorrow"},"confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_selection","intent":null,"replacement":{"from":"old customer note","to":"new customer note"},"confidence":0.91}"#
            ),
            .replaceSelection("new customer note")
        )
    }

    func testDuplicateCaseKeysDoNotBreakStructuredConfidenceDecoding() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"preset":"summary"},"replacement":null,"confidence":{"Score":0.4,"score":0.93}}"#
            ),
            .rewriteSelection(.summary)
        )
    }

    func testNormalizesPercentScaleConfidenceValues() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"concise","replacement":null,"confidence":"91"}"#
            ),
            .rewriteSelection(.concise)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":62}"#
            ),
            .some(.none)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":{"score":62}}"#
            ),
            .some(.none)
        )
    }

    func testDecodesTopLevelConfidenceAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"score":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":"ship tomorrow","probability":91}"#
            ),
            .replaceLast("ship tomorrow")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"score":62}"#
            ),
            .some(.none)
        )
    }

    func testKeepsStructuredLowConfidenceAsNone() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"rewrite_selection","intent":{"preset":"summary"},"replacement":null,"confidence":{"score":0.62}}"#
            ),
            .some(.none)
        )
    }
}
