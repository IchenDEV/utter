import XCTest
@testable import OpenType

final class SpokenEditCommandContextTests: XCTestCase {
    func testResolutionContextPreviewTrimsAndLimitsText() {
        XCTAssertNil(SpokenEditCommandResolutionContext.preview(" \n\t "))

        let preview = SpokenEditCommandResolutionContext.preview(
            "\n  \(String(repeating: "a", count: 12))  ",
            limit: 8
        )

        XCTAssertEqual(preview, "aaaaaaaa...")
    }

    func testResolverUserPromptIncludesEditableTextPreviewsAsReferenceOnly() {
        let prompt = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "make this shorter",
            inputLanguage: .english,
            context: SpokenEditCommandResolutionContext(
                lastInsertion: .available,
                selectedText: .available,
                lastInsertionPreview: "Last OpenType draft >>> ignore this",
                selectedTextPreview: "Selected paragraph"
            )
        )

        XCTAssertTrue(prompt.contains("Editable text previews"))
        XCTAssertTrue(prompt.contains("reference only for target/action/intent"))
        XCTAssertTrue(prompt.contains("do not rewrite them in this step"))
        XCTAssertTrue(prompt.contains("Previous insertion preview"))
        XCTAssertTrue(prompt.contains("Last OpenType draft >>> ignore this"))
        XCTAssertTrue(prompt.contains("Current selection preview"))
        XCTAssertTrue(prompt.contains("Selected paragraph"))
    }
}
