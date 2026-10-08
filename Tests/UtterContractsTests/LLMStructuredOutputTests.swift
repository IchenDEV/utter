import XCTest
@testable import UtterContracts

final class LLMStructuredOutputTests: XCTestCase {
    func testFirstJSONObjectDataIgnoresTrailingBraceText() throws {
        let output = """
        result:
        {"text":"ship {alpha} tomorrow","note":"quote: \\"ok\\""}
        trailing {"ignored":true}
        """

        let data = try XCTUnwrap(LLMStructuredOutput.firstJSONObjectData(from: output))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["text"], "ship {alpha} tomorrow")
        XCTAssertEqual(object["note"], #"quote: "ok""#)
    }

    func testFirstJSONObjectDataRejectsUnbalancedOutput() {
        XCTAssertNil(LLMStructuredOutput.firstJSONObjectData(from: #"prefix {"text":"unfinished""#))
    }

    func testJSONObjectDataCandidatesReturnBalancedObjectsInOrder() throws {
        let output = #"noise {"ignored":true} then {"action":"none","confidence":0}"#

        let candidates = LLMStructuredOutput.jsonObjectDataCandidates(from: output)

        XCTAssertEqual(candidates.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[0]) as? [String: Bool])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[1]) as? [String: Any])
        XCTAssertEqual(first["ignored"], true)
        XCTAssertEqual(second["action"] as? String, "none")
    }

    func testJSONObjectDataCandidatesIncludeNestedObjectsAfterWrapper() throws {
        let output = """
        Final:
        {"result":{"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.91}}
        """

        let candidates = LLMStructuredOutput.jsonObjectDataCandidates(from: output)

        XCTAssertEqual(candidates.count, 2)
        let wrapper = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[0]) as? [String: Any])
        let nested = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[1]) as? [String: Any])
        XCTAssertNotNil(wrapper["result"])
        XCTAssertEqual(nested["action"] as? String, "rewrite_selection")
    }

    func testJSONObjectDataCandidatesIncludeObjectsInsideJSONStringFields() throws {
        let output = #"""
        {"tool_call":{"arguments":"{\"action\":\"replace_last\",\"intent\":null,\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}}
        """#

        let candidates = LLMStructuredOutput.jsonObjectDataCandidates(from: output)

        XCTAssertEqual(candidates.count, 3)
        let embedded = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[2]) as? [String: Any])
        XCTAssertEqual(embedded["action"] as? String, "replace_last")
        XCTAssertEqual(embedded["replacement"] as? String, "ship tomorrow")
    }

    func testJSONObjectDataCandidatesDecodeQuotedJSONStringLiteral() throws {
        let output = #""{\"action\":\"replace_last\",\"intent\":null,\"replacement\":\"ship tomorrow\",\"confidence\":0.91}""#

        let candidates = LLMStructuredOutput.jsonObjectDataCandidates(from: output)

        XCTAssertEqual(candidates.count, 1)
        let embedded = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[0]) as? [String: Any])
        XCTAssertEqual(embedded["action"] as? String, "replace_last")
        XCTAssertEqual(embedded["replacement"] as? String, "ship tomorrow")
    }

    func testJSONValueDataCandidatesKeepOutputTextArrayTogether() throws {
        let output = """
        Final response:
        [{"type":"output_text","text":"Ship the release notes."},{"type":"output_text","text":"Then confirm QA."}]
        """

        let candidates = LLMStructuredOutput.jsonValueDataCandidates(from: output)

        XCTAssertEqual(candidates.count, 1)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[0]) as? [[String: String]])
        XCTAssertEqual(array.map { $0["text"] }, ["Ship the release notes.", "Then confirm QA."])
    }
}
