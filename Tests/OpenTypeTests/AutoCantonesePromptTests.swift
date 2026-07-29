import XCTest
@testable import OpenType

@MainActor
final class AutoCantonesePromptTests: XCTestCase {
    private func withDefaultPromptSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedUseCustomSystemPrompt = settings.useCustomSystemPrompt
        let savedCustomSystemPrompt = settings.customSystemPrompt
        let savedLanguageStyle = settings.languageStyle
        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        settings.languageStyle = .professional
        defer {
            settings.useCustomSystemPrompt = savedUseCustomSystemPrompt
            settings.customSystemPrompt = savedCustomSystemPrompt
            settings.languageStyle = savedLanguageStyle
        }
        try body()
    }

    func testAutoAndCantoneseUserPromptsDescribeTheirLanguagePolicy() {
        XCTAssertTrue(PromptBuilder.buildUserPrompt(
            text: "um hello",
            inputLanguage: .auto
        ).contains("自动语言 ASR 原文"))
        XCTAssertTrue(PromptBuilder.buildUserPrompt(
            text: "啱啱講錯咗",
            inputLanguage: .cantonese
        ).contains("粤语语音识别原文"))
    }

    func testAutoAndCantoneseSmartFormatPromptsUseLanguageSpecificPolicies() {
        let cantonese = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            screenContext: "OpenType 設定",
            screenImageAvailable: true,
            memoryContext: "啱啱講過 hotkey",
            inputLanguage: .cantonese
        )
        let automatic = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            screenContext: "OpenType 设置",
            memoryContext: "刚才提到 hotkey",
            inputLanguage: .auto
        )

        XCTAssertTrue(cantonese.contains("粤语语音转文字后处理器"))
        XCTAssertTrue(cantonese.contains("保留自然粤语表达"))
        XCTAssertTrue(cantonese.contains("不要默认改成普通话书面中文"))
        XCTAssertTrue(cantonese.contains("粤语专业整理"))
        XCTAssertTrue(cantonese.contains("final_text"))
        XCTAssertTrue(cantonese.contains("啱啱講錯咗"))
        XCTAssertTrue(cantonese.contains("屏幕文字，仅供纠错和专有名词参考"))
        XCTAssertFalse(cantonese.contains("On-screen text for correction"))

        XCTAssertTrue(automatic.contains("多语言语音转文字后处理器"))
        XCTAssertTrue(automatic.contains("自动识别中文、英文、日文、韩文、粤语"))
        XCTAssertTrue(automatic.contains("不要无故翻译成中文或英文"))
        XCTAssertTrue(automatic.contains("自动语言专业整理"))
        XCTAssertTrue(automatic.contains("final_text"))
        XCTAssertTrue(automatic.contains("um we're meeting Thursday"))
        XCTAssertTrue(automatic.contains("最近输入，仅供语境、术语、专有名词和语气参考"))
        XCTAssertFalse(automatic.contains("On-screen text for correction"))
    }

    func testAutoAndCantoneseCasualStyleKeepLanguageIntent() {
        let automatic = PromptBuilder.buildSystemPrompt(style: .casual, stylePrompt: "", inputLanguage: .auto)
        let cantonese = PromptBuilder.buildSystemPrompt(style: .casual, stylePrompt: "", inputLanguage: .cantonese)

        XCTAssertTrue(automatic.contains("自动语言、自然直接"))
        XCTAssertTrue(automatic.contains("不要无故翻译"))
        XCTAssertTrue(cantonese.contains("自然粤语、直接"))
        XCTAssertTrue(cantonese.contains("不要默认改成普通话书面中文"))
    }

    func testAutoAndCantoneseCustomPromptContractsKeepLanguageIntent() {
        withDefaultPromptSettings {
            AppSettings.shared.useCustomSystemPrompt = true
            AppSettings.shared.customSystemPrompt = "Keep product names exact."

            let automatic = PromptBuilder.buildSystemPrompt(style: .professional, stylePrompt: "", inputLanguage: .auto)
            let cantonese = PromptBuilder.buildSystemPrompt(style: .professional, stylePrompt: "", inputLanguage: .cantonese)

            XCTAssertTrue(automatic.contains("输入法输出契约"))
            XCTAssertTrue(automatic.contains("自动判断原文主要语言"))
            XCTAssertTrue(automatic.contains("final_text"))
            XCTAssertTrue(automatic.contains("不要无故翻译"))
            XCTAssertFalse(automatic.contains("Input method output contract"))

            XCTAssertTrue(cantonese.contains("输入法输出契约"))
            XCTAssertTrue(cantonese.contains("只输出最终可插入文本"))
            XCTAssertTrue(cantonese.contains("final_text"))
            XCTAssertTrue(cantonese.contains("保留自然粤语书面表达"))
            XCTAssertFalse(cantonese.contains("Input method output contract"))
        }
    }

    func testAutoAndCantoneseCommandPromptsKeepLanguageIntent() {
        let automaticSystem = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "mail body",
            inputLanguage: .auto
        )
        let cantoneseSystem = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "訊息內容",
            inputLanguage: .cantonese
        )

        XCTAssertTrue(PromptBuilder.buildCommandUserPrompt(
            text: "reply yes",
            inputLanguage: .auto
        ).contains("自动语言语音指令转写"))
        XCTAssertTrue(PromptBuilder.buildCommandUserPrompt(
            text: "覆佢話可以",
            inputLanguage: .cantonese
        ).contains("粤语语音指令转写"))

        XCTAssertTrue(automaticSystem.contains("多语言语音助手"))
        XCTAssertTrue(automaticSystem.contains("保持原语言或自然混排方式"))
        XCTAssertTrue(automaticSystem.contains("默认使用对话/选中文本的语言"))

        XCTAssertTrue(cantoneseSystem.contains("粤语语音助手"))
        XCTAssertTrue(cantoneseSystem.contains("保留自然粤语表达"))
        XCTAssertTrue(cantoneseSystem.contains("不要默认改成普通话书面中文"))
    }

    func testAutoAndCantoneseEditCommandResolverPromptsKeepLanguageIntent() {
        let context = SpokenEditCommandResolutionContext(lastInsertion: .available, selectedText: .unknown)
        let automaticSystem = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .auto)
        let cantoneseSystem = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .cantonese)
        let automaticUser = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "make this shorter",
            inputLanguage: .auto,
            context: context
        )
        let cantoneseUser = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "將呢段改短啲",
            inputLanguage: .cantonese,
            context: context
        )

        XCTAssertTrue(automaticSystem.contains("自动语言语音口令"))
        XCTAssertTrue(automaticSystem.contains("this text/この部分/이 부분/呢段"))
        XCTAssertTrue(automaticSystem.contains("不要无故翻译"))
        XCTAssertTrue(automaticUser.contains("自动语言语音口令转写"))
        XCTAssertTrue(automaticUser.contains("只分类编辑动作"))

        XCTAssertTrue(cantoneseSystem.contains("粤语语音口令"))
        XCTAssertTrue(cantoneseSystem.contains("呢段/选中嗰段/啱啱输入"))
        XCTAssertTrue(cantoneseSystem.contains("不要默认改成普通话书面中文"))
        XCTAssertTrue(cantoneseUser.contains("粤语语音口令转写"))
        XCTAssertTrue(cantoneseUser.contains("replacement 保留自然粤语表达"))
    }

    func testAutoAndCantoneseSelectionEditPromptsKeepLanguageIntent() {
        let processor = TextProcessor()
        let automatic = processor.selectionEditPrompt(
            selectedText: "Ship Friday, 金曜に出す",
            intent: .concise,
            inputLanguage: .auto
        )
        let cantonese = processor.selectionEditPrompt(
            selectedText: "啱啱講錯咗，唔係星期四，係星期五下晝開會。",
            intent: .formal,
            inputLanguage: .cantonese
        )

        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .auto).contains("多语言选中文本处理器"))
        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .auto).contains("保持选中文本原语言或自然混排方式"))
        XCTAssertTrue(automatic.contains("先判断选中文本主要语言"))
        XCTAssertTrue(automatic.contains("不要无故翻译"))

        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .cantonese).contains("粤语选中文本处理器"))
        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .cantonese).contains("不要默认改成普通话书面中文"))
        XCTAssertTrue(cantonese.contains("自然粤语书面表达"))
        XCTAssertTrue(cantonese.contains("不要默认改成普通话书面中文"))
    }
}
