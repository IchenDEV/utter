import XCTest
@testable import OpenType

final class SpokenEditCommandLLMResolverTests: XCTestCase {
    func testDecodesSelectionRewriteIntent() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"meeting_notes","replacement":null,"confidence":0.92}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":"formal","replacement":null,"confidence":0.9}"#
            ),
            .rewriteLast(.formal)
        )
    }

    func testDecodesReplacementAndStripsWrapperText() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: """
                result:
                {"action":"replace_last","intent":null,"replacement":"OpenType CLI。","confidence":0.88}
                """
            ),
            .replaceLast("OpenType CLI。")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replaceSelection","intent":null,"replacement":"ship it","confidence":0.9}"#
            ),
            .replaceSelection("ship it")
        )
    }

    func testReplacementPayloadPreservesLLMPunctuation() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":" OK! ","confidence":0.92}"#
            ),
            .replaceLast("OK!")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replaceSelection","intent":null,"replacement":"真的吗？","confidence":0.92}"#
            ),
            .replaceSelection("真的吗？")
        )
    }

    func testIgnoresNoneInvalidOrIncompleteActions() {
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"none","intent":null,"replacement":null,"confidence":0}"#
            )
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":"  ","confidence":0.91}"#
            )
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.6}"#
            )
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null}"#
            )
        )
    }

    func testResolutionTreatsStructuredRejectionsAsNone() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"none","intent":null,"replacement":null,"confidence":0}"#
            ),
            .some(.none)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"rewrite_selection","intent":"turn this into a haiku","replacement":null,"confidence":0.6}"#
            ),
            .some(.none)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"none","intent":"summary","replacement":null,"confidence":0}"#
            ),
            .some(.none)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.6}"#
            ),
            .some(.none)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"delete_selection","intent":null,"replacement":"ship it","confidence":0.92}"#
            ),
            .some(.none)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"replace_last","intent":null,"replacement":"ship it"}"#
            ),
            .some(.none)
        )
    }

    func testDecodesCustomSelectionRewriteInstruction() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"turn this into a warm customer apology with one concrete next step","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.custom("turn this into a warm customer apology with one concrete next step"))
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"写成乔布斯发布会式的三段产品介绍","replacement":null,"confidence":0.9}"#
            ),
            .rewriteSelection(.custom("写成乔布斯发布会式的三段产品介绍"))
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":"turn the last insertion into a warmer customer update","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.custom("turn the last insertion into a warmer customer update"))
        )
    }

    func testResolutionUsesNilOnlyForMalformedLLMOutput() {
        XCTAssertNil(SpokenEditCommandLLMResolver.resolution(from: "not json"))
        XCTAssertNil(SpokenEditCommandLLMResolver.resolution(from: #"{"action":"replace_last""#))
    }

    func testDecodesStringConfidenceFromLLMJSON() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":"0.82"}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"concise","replacement":null,"confidence":"91%"}"#
            ),
            .rewriteSelection(.concise)
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":"maybe"}"#
            )
        )
    }

    func testExtractsFirstBalancedJSONObjectFromChattyLLMOutput() {
        let output = """
        ```json
        {"action":"replace_last","intent":null,"replacement":"ship {alpha} tomorrow","confidence":0.92}
        ```

        Note: trailing text may contain braces like {"ignored":true}.
        """

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .replaceLast("ship {alpha} tomorrow")
        )
    }

    func testRejectsActionPayloadMismatches() {
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":"summary","replacement":"ship it","confidence":0.92}"#
            )
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"summary","replacement":"ship it","confidence":0.92}"#
            )
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":"summary","replacement":"ship it","confidence":0.92}"#
            )
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"delete_selection","intent":null,"replacement":"ship it","confidence":0.92}"#
            )
        )
        XCTAssertNil(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"undo_last_insertion","intent":"summary","replacement":null,"confidence":0.92}"#
            )
        )
    }

    func testResolverPromptConstrainedToSafeJSONActions() {
        let system = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .english)
        XCTAssertTrue(system.contains("Output exactly one JSON object"))
        XCTAssertTrue(system.contains("Allowed action values"))
        XCTAssertTrue(system.contains("only when it fully captures the user's command"))
        XCTAssertTrue(system.contains("extra audience, tone, content, format, or constraint details"))
        XCTAssertTrue(system.contains("natural-language instruction"))
        XCTAssertTrue(system.contains("rewrite_last"))
        XCTAssertTrue(system.contains("rewrite_selection"))
        XCTAssertTrue(system.contains("confidence is a number from 0 to 1"))
        XCTAssertTrue(system.contains("Do not execute arbitrary commands"))
        XCTAssertTrue(system.contains("Normal dictation"))
        XCTAssertTrue(system.contains("Voice: make this into meeting notes"))
        XCTAssertTrue(system.contains(#""action":"rewrite_selection","intent":"meeting_notes""#))
        XCTAssertTrue(system.contains("Voice: write a reply saying yes"))

        let user = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "make this a concise summary",
            inputLanguage: .english,
            context: SpokenEditCommandResolutionContext(
                lastInsertion: .unavailable,
                selectedText: .unavailable
            )
        )
        XCTAssertTrue(user.contains("Voice command transcript"))
        XCTAssertTrue(user.contains("Previous Utter insertion: unavailable"))
        XCTAssertTrue(user.contains("Current selection: unavailable"))
        XCTAssertTrue(user.contains("do not output replace_last, rewrite_last, or undo_last_insertion"))
        XCTAssertTrue(user.contains("do not output replace_selection, rewrite_selection, or delete_selection"))
        XCTAssertTrue(user.contains("make this a concise summary"))
    }

    func testResolverPromptPreservesDetailedSelectionRewriteInstructions() {
        let english = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .english)
        let chinese = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .chinese)

        XCTAssertTrue(english.contains("intent should be a concise natural-language instruction"))
        XCTAssertTrue(english.contains("preserves those details"))
        XCTAssertTrue(chinese.contains("完整保留这些细节"))
        XCTAssertTrue(chinese.contains("自然语言指令"))
    }

    func testEditCommandResolutionBudgetScalesForDetailedVoiceCommands() {
        let processor = TextProcessor()
        let short = processor.editCommandResolutionOptions(for: "make this shorter")
        let detailed = processor.editCommandResolutionOptions(
            for: String(repeating: "make this into a warm customer update with one concrete next step ", count: 4)
        )

        XCTAssertEqual(short.maxTokens, 256)
        XCTAssertEqual(detailed.maxTokens, 384)
        XCTAssertEqual(short.temperature, 0)
    }

    func testResolverPromptAllowsClearSelectionCommandsWhenSelectionIsUnknown() {
        let user = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "make this a concise summary",
            inputLanguage: .english,
            context: SpokenEditCommandResolutionContext(
                lastInsertion: .available,
                selectedText: .unknown
            )
        )

        XCTAssertTrue(user.contains("Previous Utter insertion: available"))
        XCTAssertTrue(user.contains("Current selection: unknown"))
        XCTAssertTrue(user.contains("only if the voice command clearly refers to selected text"))
        XCTAssertFalse(user.contains("Current selection: unavailable"))
    }
}
