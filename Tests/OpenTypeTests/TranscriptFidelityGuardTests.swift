import XCTest
@testable import OpenType

final class TranscriptFidelityGuardTests: XCTestCase {
    func testProtectsEntitiesTermsAndPolarity() {
        let source = "不要把 OpenType 2.5 发到 test@example.com 或 /tmp/demo.txt"
        XCTAssertNil(violation(
            source,
            "不要把 OpenType 2.5 发到 test@example.com，或 /tmp/demo.txt。",
            terms: ["OpenType"]
        ))
        XCTAssertEqual(
            violation(
                source,
                "把 OpenType 3.0 发到 test@example.com 或 /tmp/demo.txt",
                terms: ["OpenType"]
            ),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation(
                source,
                "不要把 2.5 发到 test@example.com 或 /tmp/demo.txt",
                terms: ["OpenType"]
            ),
            "dictionary_term_change"
        )
        XCTAssertEqual(
            violation(
                source,
                "把 OpenType 2.5 发到 test@example.com 或 /tmp/demo.txt",
                terms: ["OpenType"]
            ),
            "polarity_change"
        )
    }

    func testAllowsEvidenceBackedSpokenNumberAndSelfCorrectionCleanup() {
        XCTAssertNil(violation(
            "灰度从百分之二十五到三十",
            "灰度从 25%-30%"
        ))
        XCTAssertNil(violation(
            "版本是二点五",
            "版本是 2.5"
        ))
        XCTAssertNil(violation(
            "我们周四，不对，周五下午开会",
            "我们周五下午开会"
        ))
        XCTAssertNil(violation(
            "唔係星期四，係星期五下晝開會",
            "星期五下晝開會",
            language: .cantonese
        ))
    }

    func testNumberEvidenceCannotAuthorizeUnrelatedNumbers() {
        XCTAssertEqual(
            violation(
                "two tasks",
                "2 tasks at 999",
                language: .english
            ),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation(
                "版本二",
                "版本 999"
            ),
            "protected_token_change"
        )
    }

    func testAllowsEvidencePreservingRangeAndDateFormatting() {
        XCTAssertNil(violation("第1到第3步", "第 1-3 步"))
        XCTAssertNil(violation(
            "日期是2026年7月30日",
            "日期是 2026-07-30"
        ))
    }

    func testRejectsEmptyUnrelatedAndExcessiveOutputs() {
        XCTAssertEqual(violation("请把合同发给财务", ""), "empty_output")
        XCTAssertEqual(
            violation("请把合同发给财务", "明天取消发布窗口"),
            "content_drift"
        )
        XCTAssertEqual(
            violation("确认", "确认后给所有人发送一份完整的发布总结"),
            "excessive_expansion"
        )
    }

    func testRejectsTokenReorderingAndNegationScopeMovement() {
        XCTAssertEqual(
            violation("Alice 2, Bob 3", "Alice 3, Bob 2", language: .english),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation(
                "Do not deploy to staging; test production.",
                "Deploy to staging; do not test production.",
                language: .english
            ),
            "polarity_change"
        )
    }

    func testProtectsSentenceFinalEmailOpaquePathsAndQuotes() {
        XCTAssertEqual(
            violation(
                "Email test@example.com.",
                "Email test@example.org.",
                language: .english
            ),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation(#"Open "/tmp/①.txt""#, #"Open "/tmp/1.txt""#, language: .english),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation(#"Open "/tmp/My File.txt""#, "Open /tmp/My File.txt", language: .english),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation("Edit Sources/App/Foo.swift", "Edit Sources/App/Bar.swift", language: .english),
            "protected_token_change"
        )
    }

    func testDoesNotTreatEnglishNumberAbbreviationAsNegation() {
        XCTAssertNil(violation("See No. 5.", "See No. 5.", language: .english))
    }

    func testFillerCleanupDoesNotMoveOrEraseNegation() {
        XCTAssertNil(violation(
            "Do not, um, deploy.",
            "Do not deploy.",
            language: .english
        ))
        XCTAssertEqual(
            violation(
                "No deploy, but test production.",
                "Deploy, but test production.",
                language: .english
            ),
            "polarity_change"
        )
    }

    func testFillerDoesNotAuthorizeLargeDeletion() {
        XCTAssertNotNil(violation(
            "Um, please send the signed contract to finance today.",
            "Send contract.",
            language: .english
        ))
    }

    func testBoundedCustomTransformationAllowsOmissionButNotNewFacts() {
        XCTAssertNil(violation(
            "Release 2 is ready after review",
            "Release is ready",
            language: .english,
            semantic: false
        ))
        XCTAssertEqual(
            violation(
                "Release 2 is ready",
                "Release 3 is ready",
                language: .english,
                semantic: false
            ),
            "protected_token_change"
        )
        XCTAssertEqual(
            violation(
                "Release 2 is ready",
                "",
                language: .english,
                semantic: false
            ),
            "empty_output"
        )
    }

    private func violation(
        _ source: String,
        _ candidate: String,
        terms: [String] = [],
        language: InputLanguage = .chinese,
        semantic: Bool = true
    ) -> String? {
        TranscriptFidelityGuard.violation(
            source: source,
            candidate: candidate,
            protectedTerms: terms,
            inputLanguage: language,
            enforceSemanticFidelity: semantic
        )
    }
}
