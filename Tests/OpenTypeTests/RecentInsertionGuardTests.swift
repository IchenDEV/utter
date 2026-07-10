import XCTest
@testable import OpenType

final class RecentInsertionGuardTests: XCTestCase {
    func testSafeWhenCaretSitsRightAfterInsertedText() {
        XCTAssertEqual(
            RecentInsertionGuard.isReplacementSafe(
                textBeforeCaret: "Notes so far. 我们周五下午开会。",
                inserted: "我们周五下午开会。"
            ),
            true
        )
    }

    func testUnsafeWhenUserTypedAfterInsertion() {
        XCTAssertEqual(
            RecentInsertionGuard.isReplacementSafe(
                textBeforeCaret: "我们周五下午开会。对了，",
                inserted: "我们周五下午开会。"
            ),
            false
        )
    }

    func testUnsafeWhenCaretMovedIntoOlderText() {
        XCTAssertEqual(
            RecentInsertionGuard.isReplacementSafe(
                textBeforeCaret: "Some earlier paragraph",
                inserted: "我们周五下午开会。"
            ),
            false
        )
    }

    func testUnknownWhenFocusedTextIsUnreadable() {
        XCTAssertNil(
            RecentInsertionGuard.isReplacementSafe(
                textBeforeCaret: nil,
                inserted: "我们周五下午开会。"
            )
        )
    }

    func testUnknownWhenInsertedTextIsEmpty() {
        XCTAssertNil(
            RecentInsertionGuard.isReplacementSafe(textBeforeCaret: "anything", inserted: "")
        )
    }
}
