import UtterContracts
import XCTest
@testable import UtterProcessing

final class ListMarkerFidelityTests: XCTestCase {
    func testSingleDigitAfterLatinNameCanBecomeArabic() {
        for (source, candidate) in [
            ("然后 Windows 七又是怎么回事", "然后 Windows 7 又是怎么回事"),
            ("cloud 五系列或者 gpt 六系列", "cloud 5 系列或者 gpt 6 系列"),
            ("d 叉十二", "d 叉 12"),
        ] {
            XCTAssertNil(violation(source, candidate), "\(source) → \(candidate)")
        }
    }

    func testPlainChineseWordsStillCannotBecomeNumbers() {
        for (source, candidate) in [
            ("统一处理", "统 1 处理"), ("一点意见", "1 点意见"),
            ("iPhone 一下子就好", "iPhone 1 下子就好"),
            ("Windows 七又是怎么回事", "Windows 8 又是怎么回事"),
        ] {
            XCTAssertNotNil(violation(source, candidate), "\(source) → \(candidate)")
        }
    }

    func testSpokenOrdinalsRenderAsNumberedList() {
        for (source, candidate) in [
            ("第一个先看需求第二个确认时间", "1. 先看需求。\n2. 确认时间。"),
            ("首先看需求其次确认时间最后更新预算", "1. 看需求。\n2. 确认时间。\n3. 更新预算。"),
            ("一、看需求二、确认时间三、更新预算", "1. 看需求。\n2. 确认时间。\n3. 更新预算。"),
            (
                "嗯问题一线上的接口超时比较严重啊问题二登录页面偶尔打不开",
                "1. 线上的接口超时比较严重。\n2. 登录页面偶尔打不开。"
            ),
            ("一是看需求二是确认时间三是更新预算", "1. 看需求。\n2. 确认时间。\n3. 更新预算。"),
        ] {
            XCTAssertNil(violation(source, candidate), "\(source) → \(candidate)")
        }
    }

    func testListRenderingStillRejectsLostIntroAndChangedFacts() {
        XCTAssertNotNil(violation(
            "今天定了三件事第一个检查需求第二个确认时间第三个更新预算",
            "1. 检查需求\n2. 确认时间\n3. 更新预算"
        ))
        XCTAssertNotNil(violation(
            "第一个先看需求第二个确认时间",
            "1. 先看需求\n2. 确认 5 点"
        ))
        XCTAssertNotNil(violation(
            "第一个先看需求第二个确认时间",
            "2. 先看需求\n3. 确认时间"
        ))
    }

    func testSelfCorrectedTimeKeepsFinalValue() {
        XCTAssertNil(violation("三点，不对，四点开会", "4 点开会"))
        XCTAssertNotNil(violation("三点，不对，四点开会", "5 点开会"))
    }

    func testClassifierRecognizesMoreSpokenSequences() {
        for text in [
            "改一下策略，第一个就是先看需求，第二个是确认时间",
            "问题一是接口超时，问题二是登录失败",
            "一、看需求，二、确认时间，三、更新预算",
        ] {
            XCTAssertEqual(TextFormatClassifier.classify(text: text, context: nil).kind,
                           .orderedSteps, text)
        }
        XCTAssertEqual(TextFormatClassifier.classify(
            text: "我第一次来，第二天就走了", context: nil
        ).kind, .plainParagraph)
        XCTAssertEqual(TextFormatClassifier.classify(
            text: "他是第一个到的", context: nil
        ).kind, .plainParagraph)
    }

    func testEditRulesAreMarkedAsBindingInstructions() {
        let section = PromptCatalog.activeEditRulesSection(
            "所有数字都用阿拉伯数字", inputLanguage: .chinese
        )
        XCTAssertTrue(section?.contains("必须逐条遵守") == true)
        XCTAssertTrue(section?.contains("所有数字都用阿拉伯数字") == true)
    }

    private func violation(_ source: String, _ candidate: String) -> String? {
        TranscriptFidelityGuard.violation(
            source: source, candidate: candidate, protectedTerms: [],
            inputLanguage: .chinese, enforceSemanticFidelity: true
        )
    }
}
