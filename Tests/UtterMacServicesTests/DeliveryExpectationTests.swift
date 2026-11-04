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

    // MARK: accepted documents (ChatGPT keeps its placeholder inside the value and drops it on insert)

    private func accepted(_ document: String, at location: Int, length: Int = 0, insert replacement: String,
                          web: Bool) -> [String]? {
        DeliveryExpectation.acceptedDocuments(document: document, range: NSRange(location: location, length: length),
                                              replacement: replacement, isWebContentEditor: web)
    }

    /// 12 units: a word, a space, a word, then the trailing line feed, as measured in the ChatGPT composer.
    private let measuredPlaceholder = "Ask Xxxxxx\n"

    func testAnEmptyLookingWebEditorAcceptsTheTextAloneAndTheNormalComputation() {
        XCTAssertEqual(accepted(measuredPlaceholder, at: 0, insert: "你好，世界", web: true),
                       [("你好，世界" + measuredPlaceholder), "你好，世界"])
    }

    func testTheLoneNewlinePlaceholderKeepsExactlyTheTextAsBefore() {
        XCTAssertEqual(accepted("\n", at: 0, insert: "hello", web: true), ["hello"])
    }

    func testARealDraftAtTheStartOfAWebEditorAcceptsBothShapesButNeverTheOriginal() {
        let result = accepted("abc\n", at: 0, insert: "x", web: true)
        XCTAssertEqual(result, ["xabc\n", "x"])
        XCTAssertFalse(result?.contains("abc\n") ?? true)
        XCTAssertFalse(result?.contains("abc") ?? true)
    }

    func testNothingExtraIsAcceptedAwayFromTheStartOrOnNativeTargetsOrForDeletes() {
        XCTAssertEqual(accepted(measuredPlaceholder, at: 3, insert: "x", web: true), ["Askx Xxxxxx\n"])
        XCTAssertEqual(accepted(measuredPlaceholder, at: 0, length: 2, insert: "x", web: true), ["x" + String(measuredPlaceholder.dropFirst(2))])
        XCTAssertEqual(accepted(measuredPlaceholder, at: 0, insert: "x", web: false), ["x" + measuredPlaceholder])
        XCTAssertEqual(accepted(measuredPlaceholder, at: 0, insert: "", web: true), [])
    }

    func testAnUnchangedFieldIsNeverAcceptedEvenWhenTheTextEqualsTheDocument() {
        XCTAssertEqual(accepted("same", at: 0, insert: "same", web: true), ["samesame"])
        XCTAssertEqual(accepted("", at: 0, insert: "x", web: true), ["x"])
    }

    func testInvalidChangesStayNil() {
        XCTAssertNil(accepted("😀", at: 1, insert: "x", web: true))
        XCTAssertNil(accepted("\n", at: 2, insert: "x", web: true))
    }
}

