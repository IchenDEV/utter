import XCTest
@testable import UtterMacServices

final class DeliveryShapeDiagnosticTests: XCTestCase {
    func testSummaryCountsUnitsPrefixSuffixAndLineFeeds() {
        let summary = DeliveryShapeDiagnostic.summary(observed: "ab\ncd", expected: "ab\nXcd", original: "ab\ncd")
        XCTAssertEqual(summary, "readable=true observedUnits=5 expectedUnits=6 originalUnits=5 commonPrefix=3 commonSuffix=2 "
            + "observedLineFeeds=1 expectedLineFeeds=1 observedNoBreakSpaces=0 equalsOriginal=true")
    }

    func testUnreadableValueIsStated() {
        XCTAssertEqual(DeliveryShapeDiagnostic.summary(observed: nil, expected: "abc", original: nil),
                       "readable=false expectedUnits=3 originalUnits=-1")
    }

    func testNoTextOfAnyInputAppearsInTheSummary() {
        let observed = "秘密观察文本ZQXJ\u{00A0}"
        let expected = "预期内容WVKP"
        let original = "原始草稿MNBV"
        let summary = DeliveryShapeDiagnostic.summary(observed: observed, expected: expected, original: original)
        for fragment in ["秘密", "ZQXJ", "预期", "WVKP", "原始", "MNBV"] {
            XCTAssertFalse(summary.contains(fragment), "summary leaked \(fragment)")
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789= -")
        XCTAssertTrue(summary.allSatisfy { allowed.contains($0) }, summary)
        XCTAssertTrue(summary.contains("observedNoBreakSpaces=1"))
    }

    func testTheEmptyComposerShapeIsDescribedByItsCounts() {
        let summary = DeliveryShapeDiagnostic.summary(observed: "Ask Xxxxxx\n", expected: "你好", original: "Ask Xxxxxx\n")
        XCTAssertTrue(summary.contains("observedUnits=11"))
        XCTAssertTrue(summary.contains("equalsOriginal=true"))
        XCTAssertTrue(summary.contains("commonPrefix=0 commonSuffix=0"))
    }
}
