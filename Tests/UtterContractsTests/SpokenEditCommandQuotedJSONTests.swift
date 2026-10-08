import XCTest
@testable import UtterContracts

final class SpokenEditCommandQuotedJSONTests: XCTestCase {
    func testDecodesQuotedJSONCommandPayload() {
        let output = #""{\"action\":\"replace_last\",\"intent\":null,\"replacement\":\"ship tomorrow\",\"confidence\":0.91}""#

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .replaceLast("ship tomorrow")
        )
    }

    func testLaterFinalCommandBeatsEarlierQuotedExample() {
        let output = #"""
        Example:
        "{\"action\":\"rewrite_selection\",\"intent\":\"summary\",\"replacement\":null,\"confidence\":0.91}"

        Final:
        {"action":"replace_selection","intent":null,"replacement":"new customer note","confidence":0.92}
        """#

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .replaceSelection("new customer note")
        )
    }
}
