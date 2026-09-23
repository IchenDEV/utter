import AppKit
import XCTest
@testable import OpenType

@MainActor
final class TextInsertionCancellationTests: XCTestCase {
    func testCancelDuringClipboardPreparationNeverPastesAndRestoresAllTypes() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let binaryType = NSPasteboard.PasteboardType("org.utter.test.binary")
        let bytes = Data([0, 1, 255])
        pasteboard.setData(bytes, forType: binaryType)
        pasteboard.setString("original", forType: .string)
        var pastes = 0
        let task = Task {
            await TextInserter().insertViaClipboard(text: "temporary", pasteboard: pasteboard) {
                pastes += 1
                return true
            }
        }
        // The production method suspends between placing text and posting a key.
        while pasteboard.string(forType: .string) != "temporary" { await Task.yield() }
        task.cancel()
        let pasted = await task.value
        XCTAssertFalse(pasted)
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: binaryType), bytes)
    }

    func testClipboardChangedByUserIsNotOverwrittenDuringRestore() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let pasted = await TextInserter().insertViaClipboard(text: "dictation", pasteboard: pasteboard) {
            pasteboard.clearContents()
            pasteboard.setString("new user copy", forType: .string)
            return true
        }
        XCTAssertTrue(pasted)
        XCTAssertEqual(pasteboard.string(forType: .string), "new user copy")
    }
}
