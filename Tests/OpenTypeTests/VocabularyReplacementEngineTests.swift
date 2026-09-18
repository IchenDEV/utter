import XCTest
@testable import OpenType

final class VocabularyReplacementEngineTests: XCTestCase {
    private func rule(
        _ original: String,
        _ replacement: String,
        priority: Int = 0,
        order: Int = 0
    ) -> VocabularyReplacementRule {
        VocabularyReplacementRule(
            original: original,
            replacement: replacement,
            sourcePriority: priority,
            insertionOrder: order
        )
    }

    func testLongestEntryWinsAtSamePosition() {
        let rules = [
            rule("密码", "PW", order: 0),
            rule("Wi-Fi密码", "WFP", order: 1),
        ]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "Wi-Fi密码"), "WFP")
    }

    func testShortCJKEntryDoesNotRewriteIdentifierTail() {
        let rules = [rule("密码", "PW")]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "Wi-Fi密码"), "Wi-Fi密码")
        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "v密码"), "v密码")
    }

    func testMixedEntryMatchesInsideCJKText() {
        let rules = [rule("Wi-Fi密码", "WFP")]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "我的Wi-Fi密码"), "我的WFP")
        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "Wi-Fi密码在网络"), "WFP在网络")
    }

    func testShortCJKEntryStillReplacesInsideCJKText() {
        let rules = [rule("栏", "X")]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "菜单栏"), "菜单X")
    }

    func testLongerCJKEntryBeatsShorterAtSamePosition() {
        let rules = [
            rule("栏", "X", order: 0),
            rule("菜单栏", "MENU", order: 1),
        ]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "菜单栏"), "MENU")
    }

    func testReplacementsDoNotOverlapAtSamePosition() {
        let rules = [rule("甲乙", "1"), rule("乙丙", "2")]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "甲乙丙"), "1丙")
    }

    func testAsciiBoundaryBehaviorIsUnchanged() {
        let rules = [rule("api", "API")]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "rapid"), "rapid")
        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "the api, then"), "the API, then")
        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "api_key"), "api_key")
        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "Api"), "API")
    }

    func testPersonalRuleBeatsIndustryRuleAtSamePosition() {
        let rules = [
            rule("禁忌症", "personal", priority: 0, order: 0),
            rule("禁忌症", "industry", priority: 1, order: 0),
        ]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "记录禁忌症"), "记录personal")
    }

    func testEmptyOriginalRuleIsIgnored() {
        let rules = [rule("", "boom"), rule("好", "ok")]

        XCTAssertEqual(VocabularyReplacementEngine.apply(rules, to: "你好"), "你ok")
    }
}
