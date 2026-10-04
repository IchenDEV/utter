import XCTest
@testable import UtterMacServices

final class DeliveryTextChangeTests: XCTestCase {
    func testReplacementAndDeletionPreserveSurroundingUTF16Text() throws {
        let text = "前😀后"
        let replacement = try XCTUnwrap(DeliveryTextChange(document: text, range: NSRange(location: 1, length: 2), replacement: "新"))
        XCTAssertEqual(replacement.expectedDocument, "前新后")
        XCTAssertEqual(replacement.insertedRange, NSRange(location: 1, length: 1))
        let deletion = try XCTUnwrap(DeliveryTextChange(document: text, range: NSRange(location: 1, length: 2), replacement: ""))
        XCTAssertEqual(deletion.expectedDocument, "前后")
        XCTAssertEqual(deletion.insertedRange.length, 0)
    }

    func testInvalidOrSplitSurrogateRangesAreRejectedBeforeAnyEffect() {
        for range in [NSRange(location: NSNotFound, length: 1), NSRange(location: -1, length: 0),
                      NSRange(location: 1, length: Int.max), NSRange(location: 1, length: 1)] {
            XCTAssertNil(DeliveryTextChange(document: "前😀后", range: range, replacement: "new"))
        }
    }
}
