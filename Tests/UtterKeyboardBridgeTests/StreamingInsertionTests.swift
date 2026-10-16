import XCTest
@testable import UtterKeyboardBridge

final class StreamingInsertionTests: XCTestCase {
    private var stream = StreamingInsertion()

    override func setUp() {
        stream = StreamingInsertion()
        stream.begin(contextBefore: "Hello ", contextAfter: nil)
    }

    func testFirstDraftIsPureInsertion() {
        XCTAssertEqual(stream.edit(to: "今天"), StreamingEdit(deleteCount: 0, insert: "今天"))
    }

    func testGrowingDraftOnlyAppends() {
        _ = stream.edit(to: "今天")
        XCTAssertEqual(stream.edit(to: "今天下午"), StreamingEdit(deleteCount: 0, insert: "下午"))
    }

    func testRevisedTailReplacesOnlyTheChangedCharacters() {
        _ = stream.edit(to: "今天下午三点")
        XCTAssertEqual(stream.edit(to: "今天下午 3:00"), StreamingEdit(deleteCount: 2, insert: " 3:00"))
        XCTAssertEqual(stream.written, "今天下午 3:00")
    }

    func testIdenticalDraftIsEmpty() {
        _ = stream.edit(to: "abc")
        XCTAssertTrue(stream.edit(to: "abc").isEmpty)
    }

    func testShorterDraftDeletesSurplus() {
        _ = stream.edit(to: "abcdef")
        XCTAssertEqual(stream.edit(to: "abc"), StreamingEdit(deleteCount: 3, insert: ""))
    }

    func testEmojiCountsAsOneDeletion() {
        _ = stream.edit(to: "ok 👨‍👩‍👧")
        XCTAssertEqual(stream.edit(to: "ok").deleteCount, 2)
    }

    func testFreshFieldIsIntact() {
        XCTAssertTrue(stream.isIntact(contextBefore: "Hello ", contextAfter: nil, selectedText: nil))
    }

    func testSpanBeforeCursorIsIntact() {
        _ = stream.edit(to: "今天")
        XCTAssertTrue(stream.isIntact(contextBefore: "Hello 今天", contextAfter: nil, selectedText: nil))
    }

    func testCursorMovedAwayIsNotIntact() {
        _ = stream.edit(to: "今天")
        XCTAssertFalse(stream.isIntact(contextBefore: "Hel", contextAfter: "lo 今天", selectedText: nil))
    }

    func testTypedCharacterIsNotIntact() {
        _ = stream.edit(to: "今天")
        XCTAssertFalse(stream.isIntact(contextBefore: "Hello 今天x", contextAfter: nil, selectedText: nil))
    }

    func testSelectionIsNotIntact() {
        XCTAssertFalse(stream.isIntact(contextBefore: "Hello ", contextAfter: nil, selectedText: "Hello"))
    }

    func testTextAfterCursorChangingIsNotIntact() {
        XCTAssertFalse(stream.isIntact(contextBefore: "Hello ", contextAfter: "tail", selectedText: nil))
    }

    func testTruncatedHostContextStillMatches() {
        _ = stream.edit(to: "今天下午三点")
        XCTAssertTrue(stream.isIntact(contextBefore: "下午三点", contextAfter: nil, selectedText: nil))
        XCTAssertFalse(stream.isIntact(contextBefore: "下午四点", contextAfter: nil, selectedText: nil))
    }

    func testDetachedNeverWritesAgain() {
        _ = stream.edit(to: "abc")
        stream.detach()
        XCTAssertTrue(stream.edit(to: "abcdef").isEmpty)
        XCTAssertFalse(stream.isIntact(contextBefore: "Hello abc", contextAfter: nil, selectedText: nil))
        XCTAssertEqual(stream.written, "abc")
    }
}
