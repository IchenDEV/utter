import XCTest
@testable import UtterMacServices

final class DeliveryExpectationTests: XCTestCase {
    private func expected(_ document: String, at location: Int, length: Int = 0, insert replacement: String,
                          web: Bool) -> String? {
        DeliveryExpectation.expectedDocument(document: document, range: NSRange(location: location, length: length),
                                             replacement: replacement, isWebContentEditor: web)
    }

    func testLonePlaceholderOnAWebEditorExpectsTheTextWithoutItsTrailingNewline() {
        XCTAssertEqual(expected("\n", at: 0, insert: "hello", web: true), "hello")
        XCTAssertEqual(expected("\n", at: 0, insert: "第一行\n第二行", web: true), "第一行\n第二行")
    }

    func testTheSameDocumentOnANativeTargetIsComputedAsBefore() {
        XCTAssertEqual(expected("\n", at: 0, insert: "hello", web: false), "hello\n")
    }

    func testAnEmptyDocumentNeedsNoSpecialCase() {
        XCTAssertEqual(expected("", at: 0, insert: "hi", web: true), "hi")
        XCTAssertEqual(expected("", at: 0, insert: "hi", web: false), "hi")
    }

    func testDocumentsThatAreNotExactlyOnePlaceholderUseTheNormalComputation() {
        XCTAssertEqual(expected("abc", at: 3, insert: "X", web: true), "abcX")
        XCTAssertEqual(expected("abc", at: 1, length: 1, insert: "X", web: true), "aXc")
        XCTAssertEqual(expected("\n\n", at: 0, insert: "x", web: true), "x\n\n")
        XCTAssertEqual(expected("a\n", at: 0, insert: "x", web: true), "xa\n")
        XCTAssertEqual(expected(" \n", at: 0, insert: "x", web: true), "x \n")
    }

    func testThePlaceholderRuleOnlyAppliesWithTheCaretAtTheStart() {
        XCTAssertEqual(expected("\n", at: 1, insert: "hi", web: true), "\nhi")
        XCTAssertEqual(expected("\n", at: 0, length: 1, insert: "hi", web: true), "hi")
    }

    func testDeletingNeverRewritesThePlaceholder() {
        XCTAssertEqual(expected("\n", at: 0, insert: "", web: true), "\n")
    }

    func testSurrogatePairBoundariesAreStillRejected() {
        XCTAssertNil(expected("😀", at: 1, insert: "x", web: true))
        XCTAssertNil(expected("😀", at: 1, insert: "x", web: false))
        XCTAssertEqual(expected("😀", at: 2, insert: "x", web: true), "😀x")
    }

    func testInvalidRangesStillReturnNilEvenOnThePlaceholder() {
        XCTAssertNil(expected("\n", at: 2, insert: "x", web: true))
        XCTAssertNil(expected("\n", at: 0, length: 2, insert: "x", web: true))
        XCTAssertNil(expected("\n", at: -1, insert: "x", web: true))
        XCTAssertNil(expected("\n", at: 0, length: -1, insert: "x", web: true))
    }
}
