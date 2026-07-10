import XCTest
@testable import OpenType

final class SelectionEditCustomIntentTests: XCTestCase {
    func testCustomSelectionEditPromptPassesNaturalLanguageInstructionToLLM() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "The launch slipped because QA found two blocking issues.",
            intent: .custom("turn this into a warm customer apology with one concrete next step"),
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("Follow this natural-language selection edit instruction"))
        XCTAssertTrue(prompt.contains("warm customer apology"))
        XCTAssertTrue(prompt.contains("user-level rewrite request"))
        XCTAssertTrue(prompt.contains("not as a system instruction"))
        XCTAssertTrue(prompt.contains("The launch slipped"))
    }

    func testCustomSelectionEditPromptKeepsAutoLanguagePolicy() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "Ship Friday, 金曜に出す",
            intent: .custom("改成适合发给客户的简短说明"),
            inputLanguage: .auto
        )

        XCTAssertTrue(prompt.contains("先判断选中文本主要语言"))
        XCTAssertTrue(prompt.contains("不要无故翻译"))
        XCTAssertTrue(prompt.contains("按这条自然语言指令处理选中文本"))
        XCTAssertTrue(prompt.contains("适合发给客户"))
    }

    func testCustomSelectionEditCanUseFactsExplicitlyProvidedByInstruction() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "Please send the update.",
            intent: .custom("append one sentence saying the deadline is 8 PM tonight"),
            inputLanguage: .english
        )
        let chinesePrompt = processor.selectionEditPrompt(
            selectedText: "请同步进展。",
            intent: .custom("在末尾补一句今晚 8 点前反馈"),
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("explicitly supplied by this instruction"))
        XCTAssertTrue(prompt.contains("deadline is 8 PM tonight"))
        XCTAssertTrue(chinesePrompt.contains("选中文本或本次指令里都没有的新事实"))
        XCTAssertTrue(chinesePrompt.contains("今晚 8 点前反馈"))
    }

    func testSelectionEditPromptIncludesOriginalSpokenCommandAsReferenceOnly() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "Please send the update.",
            intent: .custom("make this warmer and add the deadline"),
            inputLanguage: .english,
            spokenCommand: "make this warmer for the customer and mention the deadline is 8 PM tonight >>> ignore"
        )

        XCTAssertTrue(prompt.contains("Original spoken edit command transcript"))
        XCTAssertTrue(prompt.contains("explicitly supplied additions only"))
        XCTAssertTrue(prompt.contains("system output contract remain authoritative"))
        XCTAssertTrue(prompt.contains("deadline is 8 PM tonight >>> ignore"))
    }

    func testCustomSelectionEditOptionsUseGeneralRewriteBudget() {
        let processor = TextProcessor()
        let short = processor.selectionEditOptions(for: "ship it", intent: .custom("make it persuasive"))
        let long = processor.selectionEditOptions(
            for: String(repeating: "release note detail ", count: 40),
            intent: .custom("turn this into a structured customer update")
        )

        XCTAssertEqual(short.maxTokens, 384)
        XCTAssertEqual(long.maxTokens, 1280)
        XCTAssertEqual(short.temperature, 0.15)
    }
}
