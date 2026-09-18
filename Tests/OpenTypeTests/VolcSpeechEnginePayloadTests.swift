import XCTest
@testable import OpenType

final class VolcSpeechEnginePayloadTests: XCTestCase {
    func testHotwordContextSerializesPhrasesAsWordEntries() throws {
        let context = try XCTUnwrap(
            VolcSpeechEngine.hotwordContext(for: ["OpenType", "菜单栏"])
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any]
        )
        let hotwords = try XCTUnwrap(object["hotwords"] as? [[String: String]])

        XCTAssertEqual(hotwords.compactMap { $0["word"] }, ["OpenType", "菜单栏"])
    }

    func testFullClientRequestCarriesHotwordsInCorpusContext() throws {
        let phrases = ["OpenType", "菜单栏"]
        let context = try XCTUnwrap(VolcSpeechEngine.hotwordContext(for: phrases))

        let payload = VolcSpeechEngine.fullClientRequestPayload(
            language: "zh-CN",
            hotwordContext: context
        )

        let request = try XCTUnwrap(payload["request"] as? [String: Any])
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        let corpus = try XCTUnwrap(request["corpus"] as? [String: Any])
        XCTAssertEqual(corpus["context"] as? String, context)

        let audio = try XCTUnwrap(payload["audio"] as? [String: Any])
        XCTAssertEqual(audio["language"] as? String, "zh-CN")
    }

    func testPayloadOmitsCorpusWithoutPhrases() {
        XCTAssertNil(VolcSpeechEngine.hotwordContext(for: []))
        XCTAssertNil(VolcSpeechEngine.hotwordContext(for: ["   "]))

        let payload = VolcSpeechEngine.fullClientRequestPayload(
            language: nil,
            hotwordContext: nil
        )
        let request = payload["request"] as? [String: Any]
        XCTAssertNil(request?["corpus"])
    }

    func testHotwordBudgetKeepsWholeEntriesOnly() throws {
        let phrases = (0..<150).map { "term\($0)" }
        let context = try XCTUnwrap(VolcSpeechEngine.hotwordContext(for: phrases))

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any]
        )
        let hotwords = try XCTUnwrap(object["hotwords"] as? [[String: String]])

        XCTAssertLessThanOrEqual(hotwords.count, VolcSpeechEngine.maximumHotwordCount)
        for entry in hotwords {
            XCTAssertTrue(phrases.contains(entry["word"] ?? ""), entry["word"] ?? "")
        }
    }
}
