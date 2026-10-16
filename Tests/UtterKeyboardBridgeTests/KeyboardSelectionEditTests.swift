import XCTest
@testable import UtterKeyboardBridge

final class KeyboardSelectionEditTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let document = UUID()

    func target(original: String = "你好👨‍👩‍👧‍👦") throws -> KeyboardSelectionTarget {
        try KeyboardSelectionTarget(documentID: document, selectedText: original, contextBefore: "前文 ", contextAfter: " 后文", now: time)
    }
    func proposal(original: String = "你好👨‍👩‍👧‍👦", candidate: String = "您好👨‍👩‍👧‍👦") throws -> KeyboardSelectionEdit {
        try KeyboardSelectionEdit(id: UUID(), target: target(original: original), candidate: candidate, now: time)
    }
    func apply(_ edit: inout KeyboardSelectionEdit) throws {
        let text = try edit.beginApply(documentID: document, selectedText: edit.target.original,
                                      contextBefore: "前文 ", contextAfter: " 后文", now: time)
        XCTAssertEqual(text, "您好👨‍👩‍👧‍👦")
        XCTAssertTrue(edit.confirmApply(documentID: document, selectedText: nil, contextBefore: "前文 " + text,
                                        contextAfter: " 后文", now: time))
    }

    func testApplyAndRestoreExactOriginalOnce() throws {
        var edit = try proposal()
        try apply(&edit)
        let change = try edit.beginRestore(documentID: document, selectedText: nil, contextBefore: "前文 您好👨‍👩‍👧‍👦",
                                           contextAfter: " 后文", now: time)
        XCTAssertEqual(change, StreamingEdit(deleteCount: 3, insert: "你好👨‍👩‍👧‍👦"))
        XCTAssertTrue(edit.confirmRestore(documentID: document, selectedText: nil, contextBefore: "前文 你好👨‍👩‍👧‍👦",
                                          contextAfter: " 后文", now: time))
        XCTAssertEqual(edit.phase, .restored)
        XCTAssertThrowsError(try edit.beginRestore(documentID: document, selectedText: nil, contextBefore: "前文 你好👨‍👩‍👧‍👦",
                                                   contextAfter: " 后文", now: time))
    }

    func testApplyRejectsChangedDocumentSelectionContextAndUnavailableReadback() throws {
        let cases: [(UUID?, String?, String?, String?)] = [
            (UUID(), "你好👨‍👩‍👧‍👦", "前文 ", " 后文"), (document, "别的选区", "前文 ", " 后文"),
            (document, "你好👨‍👩‍👧‍👦", "被改了 ", " 后文"), (document, "你好👨‍👩‍👧‍👦", "前文 ", " 新后文"),
            (document, "你好👨‍👩‍👧‍👦", nil, " 后文"), (document, "你好👨‍👩‍👧‍👦", "前文 ", nil),
            (nil, "你好👨‍👩‍👧‍👦", "前文 ", " 后文")
        ]
        for (id, selection, before, after) in cases {
            var edit = try proposal()
            XCTAssertThrowsError(try edit.beginApply(documentID: id, selectedText: selection, contextBefore: before, contextAfter: after, now: time))
            XCTAssertEqual(edit.phase, .cancelled)
        }
    }

    func testApplyAuthorityConsumedBeforeEffectAndUncertainCannotRetry() throws {
        var edit = try proposal()
        _ = try edit.beginApply(documentID: document, selectedText: "你好👨‍👩‍👧‍👦", contextBefore: "前文 ", contextAfter: " 后文", now: time)
        XCTAssertEqual(edit.phase, .applying)
        XCTAssertThrowsError(try edit.beginApply(documentID: document, selectedText: "你好👨‍👩‍👧‍👦", contextBefore: "前文 ", contextAfter: " 后文", now: time))
        XCTAssertFalse(edit.confirmApply(documentID: document, selectedText: nil, contextBefore: "👨‍👩‍👧‍👦", contextAfter: " 后文", now: time))
        XCTAssertEqual(edit.phase, .uncertain)
        XCTAssertThrowsError(try edit.beginRestore(documentID: document, selectedText: nil, contextBefore: "前文 您好👨‍👩‍👧‍👦", contextAfter: " 后文", now: time))
    }

    func testRestoreRejectsLaterInputSelectionContextAndMissingReadback() throws {
        let cases: [(String?, String?, String?)] = [
            (nil, "前文 您好👨‍👩‍👧‍👦后加字", " 后文"), ("选区", "前文 您好👨‍👩‍👧‍👦", " 后文"),
            (nil, "前文 您好👨‍👩‍👧‍👦", " 新后文"), (nil, nil, " 后文"), (nil, "", " 后文")
        ]
        for (selected, before, after) in cases {
            var edit = try proposal(); try apply(&edit)
            XCTAssertThrowsError(try edit.beginRestore(documentID: document, selectedText: selected, contextBefore: before, contextAfter: after, now: time))
            XCTAssertEqual(edit.phase, .cancelled)
        }
    }

    func testExpiredAndCancelledNeverApplyOrRestore() throws {
        var expired = try proposal()
        XCTAssertThrowsError(try expired.beginApply(documentID: document, selectedText: "你好👨‍👩‍👧‍👦", contextBefore: "前文 ", contextAfter: " 后文", now: time.addingTimeInterval(120)))
        var cancelled = try proposal(); cancelled.invalidate()
        XCTAssertThrowsError(try cancelled.beginApply(documentID: document, selectedText: "你好👨‍👩‍👧‍👦", contextBefore: "前文 ", contextAfter: " 后文", now: time))
        var lateRestore = try proposal(); try apply(&lateRestore)
        XCTAssertThrowsError(try lateRestore.beginRestore(documentID: document, selectedText: nil, contextBefore: "前文 您好👨‍👩‍👧‍👦", contextAfter: " 后文", now: time.addingTimeInterval(120)))
    }

    func testEmptyOversizedUnchangedAndUnsupportedInputRejected() throws {
        XCTAssertThrowsError(try KeyboardSelectionTarget(documentID: document, selectedText: "", contextBefore: "", contextAfter: "", now: time))
        XCTAssertThrowsError(try KeyboardSelectionTarget(documentID: document, selectedText: "原文", contextBefore: nil, contextAfter: "", now: time))
        XCTAssertThrowsError(try KeyboardSelectionTarget(documentID: document, selectedText: String(repeating: "a", count: 8193), contextBefore: "", contextAfter: "", now: time))
        for candidate in ["", "  \n", "你好👨‍👩‍👧‍👦", String(repeating: "a", count: 8193)] {
            XCTAssertThrowsError(try proposal(candidate: candidate))
        }
    }

    func testDecodedTargetIsRevalidatedAndDoesNotGrantAuthority() throws {
        let valid = try target()
        let data = try JSONEncoder().encode(valid)
        var fields = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        fields["original"] = ""
        let forged = try JSONDecoder().decode(KeyboardSelectionTarget.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertFalse(forged.isValid(at: time))
        XCTAssertThrowsError(try KeyboardSelectionEdit(id: UUID(), target: forged, candidate: "新文", now: time))
    }

    func testJoiningGraphemeAtSelectionEdgesCannotGrantWriteAuthority() throws {
        for (before, candidate, after) in [("a", "\u{301}", ""), ("🇦", "🇧🇨", ""), ("\r", "\n", ""), ("", "a", "\u{301}")] {
            let target = try KeyboardSelectionTarget(documentID: document, selectedText: "x", contextBefore: before, contextAfter: after, now: time)
            XCTAssertThrowsError(try KeyboardSelectionEdit(id: UUID(), target: target, candidate: candidate, now: time))
        }
    }

    func testCanonicalEquivalentEncodingIsCheckedAndRestoredExactly() throws {
        let original = "e\u{301}"
        let target = try target(original: original)
        XCTAssertFalse(target.matches(documentID: document, selectedText: "é", contextBefore: "前文 ", contextAfter: " 后文", now: time))
        var edit = try KeyboardSelectionEdit(id: UUID(), target: target, candidate: "é", now: time)
        _ = try edit.beginApply(documentID: document, selectedText: original, contextBefore: "前文 ", contextAfter: " 后文", now: time)
        XCTAssertTrue(edit.confirmApply(documentID: document, selectedText: nil, contextBefore: "前文 é", contextAfter: " 后文", now: time))
        let change = try edit.beginRestore(documentID: document, selectedText: nil, contextBefore: "前文 é", contextAfter: " 后文", now: time)
        XCTAssertEqual(change.deleteCount, 1)
        XCTAssertTrue(change.insert.utf8.elementsEqual(original.utf8))
    }
}
