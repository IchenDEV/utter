import XCTest
@testable import OpenType

final class TranscriptFidelityEdgeCaseTests: XCTestCase {
    func testPreservesPercentSignSignificantZerosAndPrecision() {
        XCTAssertEqual(violation("rollout 25", "rollout 25%"), "protected_token_change")
        XCTAssertEqual(violation("delta +5", "delta 5"), "protected_token_change")
        XCTAssertEqual(violation("code 00123", "code 123"), "protected_token_change")
        XCTAssertEqual(violation("version 2.50", "version 2.5"), "protected_token_change")
    }

    func testEnglishSpokenDigitsDecimalAndYearHaveExactEvidence() {
        XCTAssertNil(violation("code one two three", "code 123"))
        XCTAssertNil(violation("version two point five", "version 2.5"))
        XCTAssertNil(violation("year twenty twenty six", "year 2026"))
    }

    func testMeasurementUnitsAreBoundToNumbers() {
        XCTAssertEqual(
            violation("wait 3 seconds", "wait 3 minutes"),
            "protected_token_change"
        )
        XCTAssertEqual(violation("weight 5 kg", "weight 5 lb"), "protected_token_change")
        XCTAssertEqual(
            violation("temperature 12 °C", "temperature 12 °F"),
            "protected_token_change"
        )
    }

    func testRepeatedAndSharedRangeUnitsAreEquivalent() {
        XCTAssertNil(violation("wait 3 days to 5 days", "wait 3-5 days"))
        XCTAssertNil(violation("三天到五天内发版", "3-5 天内发版", language: .chinese))
    }

    func testChineseNumberEvidenceRejectsIdiomsButAllowsQuantities() {
        XCTAssertEqual(
            violation("千万不要发布", "10000000 不要发布", language: .chinese),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation("十分重要", "10 分重要", language: .chinese),
            "protected_token_change"
        )
        XCTAssertNil(violation("三天内发版", "3 天内发版", language: .chinese))
        XCTAssertNil(violation("三分钟后提醒", "3 分钟后提醒", language: .chinese))
    }

    func testKoreanOrdinalListFormattingHasEvidence() {
        XCTAssertNil(violation(
            "첫째 요구사항 확인 둘째 일정 조율 셋째 예산 업데이트",
            "1. 요구사항 확인 2. 일정 조율 3. 예산 업데이트",
            language: .korean
        ))
    }

    func testRejectsShortCommandVerbChanges() {
        XCTAssertEqual(
            violation("Approve release to production", "Cancel release to production"),
            "content_drift"
        )
        XCTAssertEqual(
            violation("允许现在发布", "禁止现在发布", language: .chinese),
            "content_drift"
        )
    }

    func testRejectsLongMiddleReplacement() {
        let source = String(repeating: "开", count: 600)
            + String(repeating: "中", count: 1_000)
            + String(repeating: "结", count: 600)
        let candidate = String(repeating: "开", count: 600)
            + String(repeating: "改", count: 1_000)
            + String(repeating: "结", count: 600)
        XCTAssertEqual(
            violation(source, candidate, language: .chinese),
            "content_drift"
        )
    }

    func testBalancedParenthesisAtEndOfURLIsProtected() {
        XCTAssertEqual(
            violation(
                "Read https://en.wikipedia.org/wiki/Function_(mathematics)",
                "Read https://en.wikipedia.org/wiki/Function_(mathematics"
            ),
            "protected_token_change"
        )
    }

    func testChinesePolarityCoversDisagreementAndNonCorrectionContrast() {
        XCTAssertEqual(
            violation("我不同意发布", "我同意发布", language: .chinese),
            "polarity_change"
        )
        XCTAssertEqual(
            violation(
                "这不是 bug，原因是配置",
                "这是 bug，原因是配置",
                language: .chinese
            ),
            "polarity_change"
        )
    }

    private func violation(
        _ source: String,
        _ candidate: String,
        language: InputLanguage = .english
    ) -> String? {
        TranscriptFidelityGuard.violation(
            source: source,
            candidate: candidate,
            protectedTerms: [],
            inputLanguage: language,
            enforceSemanticFidelity: true
        )
    }
}
