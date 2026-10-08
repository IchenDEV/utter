import XCTest
@testable import UtterProcessing

final class CommandOutputCleanerTests: XCTestCase {
    func testGeneratedReplyScaffoldingIsRemoved() {
        XCTAssertEqual(CommandOutputCleaner.clean("以下是回复：\n谢谢邀请，我会参加。"), "谢谢邀请，我会参加。")
        XCTAssertEqual(CommandOutputCleaner.clean("好的，以下是回复：谢谢邀请，我会参加。"), "谢谢邀请，我会参加。")
        XCTAssertEqual(CommandOutputCleaner.clean("Here is the reply:\nThanks for the invitation."), "Thanks for the invitation.")
        XCTAssertEqual(CommandOutputCleaner.clean(#"{"final_text":"以下是回复：谢谢。"}"#), "以下是回复：谢谢。")
    }

    func testDictatedLabelsRemainPartOfOrdinaryFormatting() {
        let text = "以下是回复：\n谢谢邀请，我会参加。"
        XCTAssertEqual(FormattedOutputCleaner.clean(text), text)
        XCTAssertEqual(CommandOutputCleaner.clean("感谢您的邮件。\n以下是回复：这句话属于正文。"), "感谢您的邮件。\n以下是回复：这句话属于正文。")
    }
}
