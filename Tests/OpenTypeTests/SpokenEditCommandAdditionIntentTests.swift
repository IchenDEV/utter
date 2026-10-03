import UtterProcessing
import UtterContracts
import XCTest
@testable import OpenType

final class SpokenEditCommandAdditionIntentTests: XCTestCase {
    func testResolverPromptTreatsExplicitAdditionsAsLLMRewriteInstructions() {
        let english = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .english)
        let chinese = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .chinese)

        XCTAssertTrue(english.contains("extend, add explicitly supplied content"))
        XCTAssertTrue(english.contains("rewrite/edit request for the referenced text"))
        XCTAssertTrue(chinese.contains("改写、补充、追加"))
        XCTAssertTrue(chinese.contains("目标文本改写/补充要求"))
    }

    func testResolverDecodesCustomAdditionIntentForLastInsertion() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":"append one sentence saying the deadline is 8 PM tonight","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.custom("append one sentence saying the deadline is 8 PM tonight"))
        )
    }
}
