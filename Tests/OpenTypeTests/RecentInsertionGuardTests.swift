import XCTest
@testable import OpenType

final class RecentInsertionGuardTests: XCTestCase {
    func testSafeWhenCaretSitsRightAfterInsertedText() {
        let prefix = "Notes so far. "
        let inserted = "我们周五下午开会。"
        let range = NSRange(location: prefix.utf16.count, length: inserted.utf16.count)

        XCTAssertEqual(
            RecentInsertionGuard.isReplacementSafe(
                sameTarget: true,
                currentSelection: NSRange(location: NSMaxRange(range), length: 0),
                insertedRange: range,
                currentText: prefix + inserted,
                inserted: inserted
            ),
            true
        )
    }

    func testUnsafeWhenUserTypedAfterInsertion() {
        let inserted = "我们周五下午开会。"
        let range = NSRange(location: 0, length: inserted.utf16.count)

        XCTAssertEqual(
            RecentInsertionGuard.isReplacementSafe(
                sameTarget: true,
                currentSelection: NSRange(location: (inserted + "对了，").utf16.count, length: 0),
                insertedRange: range,
                currentText: inserted + "对了，",
                inserted: inserted
            ),
            false
        )
    }

    func testUnsafeWhenCaretMovedIntoOlderText() {
        let inserted = "我们周五下午开会。"
        let range = NSRange(location: 0, length: inserted.utf16.count)

        XCTAssertEqual(
            RecentInsertionGuard.isReplacementSafe(
                sameTarget: true,
                currentSelection: NSRange(location: 4, length: 0),
                insertedRange: range,
                currentText: inserted,
                inserted: inserted
            ),
            false
        )
    }

    func testUnsafeWhenFocusedTextIsUnreadable() {
        XCTAssertFalse(
            RecentInsertionGuard.isReplacementSafe(
                sameTarget: true,
                currentSelection: NSRange(location: 10, length: 0),
                insertedRange: NSRange(location: 0, length: 10),
                currentText: nil,
                inserted: "我们周五下午开会。"
            )
        )
    }

    func testUnsafeWhenInsertedTextIsEmpty() {
        XCTAssertFalse(
            RecentInsertionGuard.isReplacementSafe(
                sameTarget: true,
                currentSelection: NSRange(location: 0, length: 0),
                insertedRange: NSRange(location: 0, length: 0),
                currentText: "anything",
                inserted: ""
            )
        )
    }

    func testUnsafeAtIdenticalTextInAnotherLocation() {
        let inserted = "same text"
        let currentText = "same text / same text"
        let originalRange = NSRange(location: 0, length: inserted.utf16.count)

        XCTAssertFalse(
            RecentInsertionGuard.isReplacementSafe(
                sameTarget: true,
                currentSelection: NSRange(location: currentText.utf16.count, length: 0),
                insertedRange: originalRange,
                currentText: currentText,
                inserted: inserted
            )
        )
    }

    func testUnsafeWhenFocusedElementChanged() {
        let inserted = "same text"
        let range = NSRange(location: 0, length: inserted.utf16.count)

        XCTAssertFalse(
            RecentInsertionGuard.isReplacementSafe(
                sameTarget: false,
                currentSelection: NSRange(location: NSMaxRange(range), length: 0),
                insertedRange: range,
                currentText: inserted,
                inserted: inserted
            )
        )
    }
}
