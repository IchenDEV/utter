import XCTest
@testable import UtterMacServices

final class WebContentEditorSignatureTests: XCTestCase {
    func testChromiumNodeIdentifierMarksAWebContentEditor() {
        XCTAssertTrue(WebContentEditorSignature.matches(
            attributeNames: ["AXRole", "AXValue", "ChromeAXNodeId", "AXDOMClassList", "AXSelectedText"]))
    }

    func testNativeFieldsAreNotClassified() {
        XCTAssertFalse(WebContentEditorSignature.matches(
            attributeNames: ["AXRole", "AXValue", "AXSelectedText", "AXSelectedTextRange", "AXNumberOfCharacters"]))
        XCTAssertFalse(WebContentEditorSignature.matches(attributeNames: []))
    }

    func testTheDOMClassListAloneIsNotEnoughBecauseWebKitExposesIt() {
        XCTAssertFalse(WebContentEditorSignature.matches(attributeNames: ["AXRole", "AXValue", "AXDOMClassList"]))
    }

    func testTheAttributeNameIsMatchedExactly() {
        XCTAssertFalse(WebContentEditorSignature.matches(attributeNames: ["chromeaxnodeid", "ChromeAXNodeId2"]))
    }
}
