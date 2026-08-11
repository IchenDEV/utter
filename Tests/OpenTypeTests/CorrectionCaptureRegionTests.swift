import XCTest
@testable import OpenType

final class CorrectionCaptureRegionTests: XCTestCase {
    func testFindsEditedInsertionBetweenStableAnchors() throws {
        let before = "Prefix | Open Tape | Suffix"
        let inserted = "Open Tape"
        let range = (before as NSString).range(of: inserted)
        let locator = try XCTUnwrap(CorrectionCaptureRegionLocator(
            documentText: before,
            insertedRange: range
        ))

        XCTAssertEqual(
            locator.editedText(in: "Prefix | OpenType | Suffix"),
            "OpenType"
        )
    }

    func testFindsEditedInsertionAtDocumentEnd() throws {
        let before = "Existing text. Original sentence."
        let inserted = "Original sentence."
        let range = (before as NSString).range(of: inserted)
        let locator = try XCTUnwrap(CorrectionCaptureRegionLocator(
            documentText: before,
            insertedRange: range
        ))

        XCTAssertEqual(
            locator.editedText(in: "Existing text. Corrected sentence."),
            "Corrected sentence."
        )
    }

    func testRejectsWhenBoundaryAnchorChanged() throws {
        let before = "Stable prefix | inserted | stable suffix"
        let range = (before as NSString).range(of: "inserted")
        let locator = try XCTUnwrap(CorrectionCaptureRegionLocator(
            documentText: before,
            insertedRange: range
        ))

        XCTAssertNil(locator.editedText(in: "Different prefix | corrected | stable suffix"))
    }
}
