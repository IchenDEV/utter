import XCTest
@testable import UtterContracts

final class SpokenEditEvidenceTests: XCTestCase {
    private let available = SpokenEditCommandResolutionContext(lastInsertion: .available, selectedText: .available)

    func testReplyNeverUsesAnExistingAnchorWithoutAnExplicitEdit() {
        for transcript in ["帮我回复", "回复这封邮件", "再帮我回复", "write a reply saying yes", "reply to the previous email"] {
            XCTAssertFalse(SpokenEditEvidence.allows(.rewriteLast(.reply), transcript: transcript, context: available), transcript)
            XCTAssertFalse(SpokenEditEvidence.allows(.rewriteSelection(.reply), transcript: transcript, context: available), transcript)
        }
        XCTAssertFalse(SpokenEditEvidence.allows(.rewriteLast(.reply), transcript: "回复上一段输入", context: available))
        XCTAssertTrue(SpokenEditEvidence.allows(.rewriteLast(.reply), transcript: "把上一段输入改成一封回复", context: available))
    }

    func testBothOperationAndMatchingEditableObjectAreRequired() {
        XCTAssertTrue(SpokenEditEvidence.allows(.rewriteLast(.formal), transcript: "把刚才输入改得正式一点", context: available))
        XCTAssertTrue(SpokenEditEvidence.allows(.rewriteSelection(.concise), transcript: "make this text shorter", context: available))
        XCTAssertTrue(SpokenEditEvidence.allows(.replaceSelection("明天见"), transcript: "把选中内容替换成明天见", context: available))
        XCTAssertTrue(SpokenEditEvidence.allows(.deleteSelection, transcript: "删除选中的文字", context: available))
        XCTAssertTrue(SpokenEditEvidence.allows(.undoLastInsertion, transcript: "撤销刚才的输入", context: available))
        XCTAssertFalse(SpokenEditEvidence.allows(.rewriteLast(.formal), transcript: "把选中内容改得正式一点", context: available))
        XCTAssertFalse(SpokenEditEvidence.allows(.deleteSelection, transcript: "这封邮件说要删除服务器", context: available))
        XCTAssertFalse(SpokenEditEvidence.allows(.rewriteLast(.summary), transcript: "上一段输入是会议记录", context: available))
    }

    func testUnavailableOrUnknownTargetsCannotBeEdited() {
        let stale = SpokenEditCommandResolutionContext(lastInsertion: .unavailable, selectedText: .unknown)
        XCTAssertFalse(SpokenEditEvidence.allows(.rewriteLast(.formal), transcript: "把刚才输入改得正式一点", context: stale))
        XCTAssertFalse(SpokenEditEvidence.allows(.deleteSelection, transcript: "删除选中内容", context: stale))
    }
}
