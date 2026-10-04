import UtterContracts
import XCTest
@testable import UtterProcessing

final class SpokenQuantityFidelityTests: XCTestCase {
    func testTimeAndCommonQuantitiesCanUseArabicDigits() {
        let examples = [
            ("周五下午三点", "周五下午 3 点"),
            ("三件事", "3 件事"),
            ("三项任务", "3 项任务"),
            ("三条建议", "3 条建议"),
            ("三号开会", "3 号开会"),
            ("六月三号开会", "6 月 3 号开会"),
            ("下午三点二十分开会", "下午 3 点 20 分开会"),
            ("下午三点二十分开会", "下午 3:20 开会"),
            ("版本二点五", "版本 2.5"),
            ("百分之三", "3%"),
        ]
        for (source, candidate) in examples {
            XCTAssertNil(violation(source, candidate), "\(source) → \(candidate)")
        }
    }

    func testFormattingCannotChangeQuantityUnitOrTime() {
        let examples = [
            ("三件事", "4 件事"), ("三件事", "3 项事"),
            ("三项任务", "3 条任务"), ("三号开会", "3 个开会"),
            ("下午三点二十分开会", "下午 3.2 分开会"),
            ("下午三点二十分开会", "下午 3 点 30 分开会"),
            ("下午三点开会", "下午 3 分开会"),
            ("三件事", "3 件事和 999 个问题"),
            ("Alice 两项，Bob 三项", "Alice 3 项，Bob 2 项"),
            ("Alice 两项，Bob 三项", "Bob 2 项，Alice 3 项"),
        ]
        for (source, candidate) in examples {
            XCTAssertNotNil(violation(source, candidate), "\(source) → \(candidate)")
        }
    }

    func testNonNumericWordsDoNotAuthorizeNewNumbers() {
        for (source, candidate) in [
            ("统一处理", "统 1 处理"), ("一点意见", "1 点意见"),
            ("千万不要发布", "10000000 不要发布"),
        ] {
            XCTAssertNotNil(violation(source, candidate), source)
        }
    }

    func testSharedContextCannotHideExchangedNumberOwners() {
        let context = "按照已经确认的发布计划，完成检查和复核后再汇总本次任务。"
        XCTAssertNotNil(violation(
            context + "Alice 两项，Bob 三项。" + context,
            context + "Bob 2 项，Alice 3 项。" + context
        ))
    }

    func testNarrativeOrdinalsAreNotListEvidence() {
        XCTAssertEqual(TextFormatClassifier.classify(
            text: "我第一次来，第二天就走了", context: nil
        ).kind, .plainParagraph)
        XCTAssertEqual(TextFormatClassifier.classify(
            text: "今天定了三件事：第一检查需求，第二确认时间，第三更新预算", context: nil
        ).kind, .orderedSteps)
    }

    func testListFormattingPreservesIntroAndExistingFacts() {
        XCTAssertNil(violation(
            "今天定了三件事：第一检查需求，第二确认时间，第三更新预算",
            "今天定了 3 件事：\n1. 检查需求\n2. 确认时间\n3. 更新预算"
        ))
        XCTAssertNotNil(violation(
            "今天定了三件事：第一检查需求，第二确认时间，第三更新预算",
            "1. 检查需求\n2. 确认时间\n3. 更新预算"
        ))
    }

    private func violation(_ source: String, _ candidate: String) -> String? {
        TranscriptFidelityGuard.violation(source: source, candidate: candidate,
            protectedTerms: [], inputLanguage: .chinese, enforceSemanticFidelity: true)
    }
}
