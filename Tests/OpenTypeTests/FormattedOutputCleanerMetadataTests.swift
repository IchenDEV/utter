import XCTest
@testable import OpenType

final class FormattedOutputCleanerMetadataTests: XCTestCase {
    func testKeepsJSONWithCertaintyMetadataVerbatim() {
        // Formatting prompts never request JSON output, so JSON-looking text is
        // dictated content and must not be mined for fields.
        let llmOutput = """
        {"text":"Ship the release notes today.","certainty":0.91}
        """

        XCTAssertEqual(FormattedOutputCleaner.clean(llmOutput), llmOutput)
    }

    func testKeepsJSONWithJustificationMetadataVerbatim() {
        let llmOutput = """
        {"text":"Ship the release notes today.","justification":"best final text"}
        """

        XCTAssertEqual(FormattedOutputCleaner.clean(llmOutput), llmOutput)
    }
}
