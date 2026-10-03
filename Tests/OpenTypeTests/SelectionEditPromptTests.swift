import UtterContracts
import XCTest
@testable import OpenType

final class SelectionEditPromptTests: XCTestCase {
    private func withCleanDictionary(_ body: () throws -> Void) rethrows {
        let savedEntries = PersonalDictionary.shared.entries
        let savedRules = PersonalDictionary.shared.editRules
        PersonalDictionary.shared.entries = []
        PersonalDictionary.shared.editRules = []
        defer {
            PersonalDictionary.shared.entries = savedEntries
            PersonalDictionary.shared.editRules = savedRules
        }
        try body()
    }

    func testSelectionEditPromptUsesSelectedTextAndInstruction() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "ship it today",
            intent: .formal,
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("Instruction:"))
        XCTAssertTrue(prompt.contains("Selected text:"))
        XCTAssertTrue(prompt.contains("ship it today"))
        XCTAssertTrue(prompt.contains("formal"))
    }

    func testChineseSelectionEditPromptUsesSelectedTextAndInstruction() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "今天发版",
            intent: .concise,
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("指令："))
        XCTAssertTrue(prompt.contains("选中文本："))
        XCTAssertTrue(prompt.contains("今天发版"))
        XCTAssertTrue(prompt.contains("压缩"))
    }

    func testSelectionEditPromptCanIncludeMemoryContextForLLMReference() {
        let processor = TextProcessor()
        let context = InputContext(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "#release",
            outputMode: .command,
            inputLanguage: .english,
            source: .menuBar
        )
        let english = processor.selectionEditPrompt(
            selectedText: "please update the model name",
            intent: .formal,
            inputLanguage: .english,
            memoryContext: "Use OpenType and Qwen spelling.",
            inputContext: context
        )
        let chinese = processor.selectionEditPrompt(
            selectedText: "把模型名改一下",
            intent: .formal,
            inputLanguage: .chinese,
            memoryContext: "刚才提到 OpenType 和千问。"
        )

        XCTAssertTrue(english.contains("Recent input for context, terminology, proper nouns, and tone only"))
        XCTAssertTrue(english.contains("Do not add new facts"))
        XCTAssertTrue(english.contains("Use OpenType and Qwen spelling."))
        XCTAssertTrue(english.contains("Current input target"))
        XCTAssertTrue(english.contains("- App: Slack"))
        XCTAssertTrue(english.contains("- Window: #release"))
        XCTAssertTrue(chinese.contains("最近输入，仅供语境、术语、专有名词和语气参考"))
        XCTAssertTrue(chinese.contains("不要把这里的新事实加入输出"))
        XCTAssertTrue(chinese.contains("刚才提到 OpenType 和千问。"))
    }

    func testSelectionEditSystemPromptRejectsOutputWrappers() {
        let processor = TextProcessor()
        let english = processor.selectionEditSystemPrompt(inputLanguage: .english)
        let chinese = processor.selectionEditSystemPrompt(inputLanguage: .chinese)

        XCTAssertTrue(english.contains("labels/preambles/notes"))
        XCTAssertTrue(english.contains("code fences"))
        XCTAssertTrue(english.contains("only when the instruction explicitly asks"))
        XCTAssertTrue(chinese.contains("输出标签、开场白、备注、引号说明或代码围栏"))
        XCTAssertTrue(chinese.contains("只有指令明确要求 Markdown、列表、表格或结构化章节"))
    }

    func testSelectionEditOutputDoesNotFallbackToOriginalSelection() {
        let processor = TextProcessor()
        let cleaned = processor.cleanSelectionEditOutput("<think>trying to rewrite</think>", inputLanguage: .english)
        XCTAssertEqual(cleaned, "")
    }

    func testSelectionEditSystemPromptIncludesPersonalContextForLLM() {
        withCleanDictionary {
            PersonalDictionary.shared.entries = [
                DictionaryEntry(original: "open type", replacement: "OpenType", enabled: true),
                DictionaryEntry(original: "skip brand", replacement: "SkipBrand", enabled: false),
            ]
            PersonalDictionary.shared.editRules = [
                EditRule(description: "Prefer concise release-note wording.", enabled: true),
                EditRule(description: "Ignore this disabled selection rule.", enabled: false),
            ]

            let processor = TextProcessor()
            let chinese = processor.selectionEditSystemPromptWithPersonalContext(inputLanguage: .chinese)
            let english = processor.selectionEditSystemPromptWithPersonalContext(inputLanguage: .english)

            XCTAssertTrue(chinese.contains("你是选中文本处理器"))
            XCTAssertTrue(chinese.contains("个人词库："))
            XCTAssertTrue(chinese.contains("open type -> OpenType"))
            XCTAssertTrue(chinese.contains("额外编辑规则："))
            XCTAssertTrue(chinese.contains("Prefer concise release-note wording."))
            XCTAssertFalse(chinese.contains("SkipBrand"))
            XCTAssertFalse(chinese.contains("disabled selection"))
            XCTAssertTrue(english.contains("You process selected text"))
            XCTAssertTrue(english.contains("Personal dictionary:"))
            XCTAssertTrue(english.contains("Extra edit rules:"))
        }
    }

    func testSelectionEditOptionsScaleWithIntentAndLength() {
        let processor = TextProcessor()
        let shortMeetingNotes = processor.selectionEditOptions(for: "ship it", intent: .meetingNotes)
        let longMeetingNotes = processor.selectionEditOptions(
            for: String(repeating: "release notes ", count: 40),
            intent: .meetingNotes
        )
        let title = processor.selectionEditOptions(for: String(repeating: "title ", count: 80), intent: .title)
        let decisions = processor.selectionEditOptions(for: "ship after QA", intent: .decisions)
        let friendlyReply = processor.selectionEditOptions(for: "sounds good", intent: .replyFriendly)

        XCTAssertEqual(shortMeetingNotes.maxTokens, 640)
        XCTAssertEqual(longMeetingNotes.maxTokens, 1536)
        XCTAssertEqual(title.maxTokens, 96)
        XCTAssertEqual(decisions.temperature, 0.10)
        XCTAssertEqual(friendlyReply.temperature, 0.18)
    }

    func testSelectionCasualPromptKeepsMeaningNatural() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "Please provide the update when available.",
            intent: .casual,
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("casual"))
        XCTAssertTrue(prompt.contains("friendly"))
        XCTAssertTrue(prompt.contains("without adding new facts"))
    }

    func testChineseSelectionCasualPromptKeepsMeaningNatural() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "请在方便时同步进展。",
            intent: .casual,
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("口语"))
        XCTAssertTrue(prompt.contains("亲切"))
        XCTAssertTrue(prompt.contains("不添加新事实"))
    }

    func testSelectionExpandPromptDevelopsExistingPointsOnly() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "Ship the fix after tests pass.",
            intent: .expand,
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("fuller"))
        XCTAssertTrue(prompt.contains("existing points"))
        XCTAssertTrue(prompt.contains("without adding new facts"))
    }

    func testChineseSelectionExpandPromptDevelopsExistingPointsOnly() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "测试通过后发版。",
            intent: .expand,
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("扩写"))
        XCTAssertTrue(prompt.contains("已有要点"))
        XCTAssertTrue(prompt.contains("不添加新事实"))
    }

    func testSelectionProofreadPromptKeepsCorrectionScopeNarrow() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "ship teh fix",
            intent: .proofread,
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("spelling"))
        XCTAssertTrue(prompt.contains("grammar"))
        XCTAssertTrue(prompt.contains("preserving meaning"))
    }

    func testChineseSelectionProofreadPromptKeepsCorrectionScopeNarrow() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "今天发板",
            intent: .proofread,
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("错别字"))
        XCTAssertTrue(prompt.contains("语法"))
        XCTAssertTrue(prompt.contains("保留原意"))
    }

    func testSelectionBulletListPromptRequiresMarkdownBullets() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "fix login then run tests",
            intent: .bulletList,
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("Markdown bullet list"))
        XCTAssertTrue(prompt.contains("- "))
        XCTAssertTrue(prompt.contains("without adding new facts"))
    }

    func testChineseSelectionBulletListPromptRequiresMarkdownBullets() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "修登录 跑测试",
            intent: .bulletList,
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("Markdown 无序列表"))
        XCTAssertTrue(prompt.contains("- "))
        XCTAssertTrue(prompt.contains("不添加新事实"))
    }

    func testSelectionNumberedListPromptRequiresMarkdownNumbers() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "open settings then choose model",
            intent: .numberedList,
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("Markdown numbered list"))
        XCTAssertTrue(prompt.contains("1."))
        XCTAssertTrue(prompt.contains("2."))
    }

    func testChineseSelectionNumberedListPromptRequiresMarkdownNumbers() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "打开设置 选择模型",
            intent: .numberedList,
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("Markdown 编号列表"))
        XCTAssertTrue(prompt.contains("1."))
        XCTAssertTrue(prompt.contains("2."))
    }

    func testSelectionChecklistPromptRequiresMarkdownTasks() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "fix login and run tests",
            intent: .checklist,
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("Markdown checklist"))
        XCTAssertTrue(prompt.contains("- [ ]"))
        XCTAssertTrue(prompt.contains("without adding new facts"))
    }

    func testChineseSelectionChecklistPromptRequiresMarkdownTasks() {
        let processor = TextProcessor()
        let prompt = processor.selectionEditPrompt(
            selectedText: "修登录 跑测试",
            intent: .checklist,
            inputLanguage: .chinese
        )

        XCTAssertTrue(prompt.contains("Markdown 待办清单"))
        XCTAssertTrue(prompt.contains("- [ ]"))
        XCTAssertTrue(prompt.contains("不添加新事实"))
    }
}
