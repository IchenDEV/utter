import XCTest
@testable import UtterContracts

final class SpokenEditCommandIntentValueTests: XCTestCase {
    func testDecodesStyleIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"style":"formal","reason":"requested tone"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.formal)
        )
    }

    func testDecodesFormatIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":{"format":"bullet_points","note":"list output"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.bulletList)
        )
    }

    func testDecodesCategoryIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"category":"meeting_summary"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
    }

    func testDecodesTypeAndKindIntentObjectsAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"type":"summary","reason":"best preset"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":{"kind":"bullet_list","confidence":0.91},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.bulletList)
        )
    }

    func testDecodesTopLevelFormatAndCategoryAsIntent() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","format":"numbered_points","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.numberedList)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","category":"main_points","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.keyPoints)
        )
    }

    func testDecodesTopLevelInstructionGoalAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","edit_instruction":"make this warmer for a customer","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.custom("make this warmer for a customer"))
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","objective":"turn this into a concise launch update","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.custom("turn this into a concise launch update"))
        )
    }

    func testDecodesInstructionGoalObjectsWithoutMetadataNoise() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"goal":"make this warmer for a customer","reason":"contains extra tone"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.custom("make this warmer for a customer"))
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":{"rewrite_instruction":"turn this into a concise launch update","note":"adapter field name"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.custom("turn this into a concise launch update"))
        )
    }

    func testDecodesTargetStyleIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"target_style":"casual","reason":"requested tone"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.casual)
        )
    }

    func testDecodesCommonPresetAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"action_item","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.actionItems)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"reply_english","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.replyInEnglish)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"translate_chinese","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.translateToChinese)
        )
    }
}
