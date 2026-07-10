import XCTest
@testable import OpenType

@MainActor
final class PromptBuilderTests: XCTestCase {
    private func withCleanSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedUseCustomSystemPrompt = settings.useCustomSystemPrompt
        let savedCustomSystemPrompt = settings.customSystemPrompt
        let savedInputLanguage = settings.inputLanguage
        let savedLanguageStyle = settings.languageStyle
        let savedEnableMemory = settings.enableMemory
        let savedMemoryWindow = settings.memoryWindowMinutes
        let savedEnableInstantInsert = settings.enableInstantInsert
        let savedEntries = PersonalDictionary.shared.entries
        let savedRules = PersonalDictionary.shared.editRules
        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        settings.inputLanguage = .chinese
        settings.languageStyle = .professional
        settings.enableMemory = true
        settings.memoryWindowMinutes = 30
        settings.enableInstantInsert = false
        PersonalDictionary.shared.entries = []
        PersonalDictionary.shared.editRules = []
        defer {
            settings.useCustomSystemPrompt = savedUseCustomSystemPrompt
            settings.customSystemPrompt = savedCustomSystemPrompt
            settings.inputLanguage = savedInputLanguage
            settings.languageStyle = savedLanguageStyle
            settings.enableMemory = savedEnableMemory
            settings.memoryWindowMinutes = savedMemoryWindow
            settings.enableInstantInsert = savedEnableInstantInsert
            PersonalDictionary.shared.entries = savedEntries
            PersonalDictionary.shared.editRules = savedRules
        }
        try body()
    }

    func testBuildUserPromptUsesLanguageSpecificWrappers() {
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "嗯 今天开会",
            inputLanguage: .chinese
        ), "以下是语音识别原文。请先在内部理解用户的口述意图，判断错别字、同音词、误识别词、漏字、多字、口述标点、数字单位、时间范围和专有名词，再直接输出整理后的最终文本：\n\(PromptTextBlock.block("嗯 今天开会"))")
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "um hello",
            inputLanguage: .english
        ), "Raw ASR transcript. Internally infer the user's spoken intent, including punctuation commands, numbers, units, date/time ranges, typos, homophones, ASR substitutions, missing or extra words, and proper nouns, then output only the final rewritten text:\n\(PromptTextBlock.block("um hello"))")
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "こんにちは",
            inputLanguage: .japanese
        ), "日本語の音声認識原文です。口述意図、誤認識、同音語、抜けた語、余分な語、口述された句読点、数字、単位、日時、範囲、固有名詞を内部で判断し、最終テキストだけを出力してください：\n\(PromptTextBlock.block("こんにちは"))")
    }

    func testBuildCommandUserPromptUsesLanguageSpecificWrappers() {
        XCTAssertEqual(PromptBuilder.buildCommandUserPrompt(
            text: "帮我回复他 可以",
            inputLanguage: .chinese
        ), "以下是用户的语音指令转写。请先在内部理解真实指令意图，处理同音词、误识别、漏字、多字、自我纠正和口述格式，再只输出可直接插入或发送的结果：\n\(PromptTextBlock.block("帮我回复他 可以"))")
        XCTAssertEqual(PromptBuilder.buildCommandUserPrompt(
            text: "reply yes that works",
            inputLanguage: .english
        ), "Voice command transcript. Internally infer the intended command, accounting for homophones, ASR substitutions, missing or extra words, self-corrections, and spoken formatting, then output only the text to insert or send:\n\(PromptTextBlock.block("reply yes that works"))")
    }

    func testSystemPromptIncludesChineseStyleScreenAndMemoryContext() {
        withCleanSettings {
            let inputContext = InputContext(
                appName: "备忘录",
                bundleIdentifier: "com.apple.Notes",
                windowTitle: "发布计划",
                textBeforeSelection: "我们刚才讨论到 OpenType 的",
                selectedText: "快捷键",
                textAfterSelection: "体验需要更自然。",
                outputMode: .processed,
                inputLanguage: .chinese,
                source: .menuBar
            )
            let prompt = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "更正式",
                screenContext: "OpenType 设置",
                memoryContext: "刚才提到了快捷键",
                inputContext: inputContext,
                inputLanguage: .chinese
            )

            XCTAssertTrue(prompt.contains("力度要高于轻度润色"))
            XCTAssertTrue(prompt.contains("风格：专业整理"))
            XCTAssertTrue(prompt.contains("同音错字、近音错字、漏字、多字"))
            XCTAssertTrue(prompt.contains("智能理解口述格式意图"))
            XCTAssertTrue(prompt.contains("百分之二十五到三十"))
            XCTAssertTrue(prompt.contains("输出：把灰度比例改为 25%-30%，发布窗口改到下午 3 点到 4 点。"))
            XCTAssertTrue(prompt.contains("输出标签、开场白、备注、引号说明或代码围栏"))
            XCTAssertTrue(prompt.contains("final_text"))
            XCTAssertTrue(prompt.contains("普通说明、状态同步和判断句不要强行改成编号列表"))
            XCTAssertTrue(prompt.contains("只有原文明显是步骤、清单或待办时，才输出 1. 2. 3."))
            XCTAssertTrue(prompt.contains("专业整理补充示例："))
            XCTAssertTrue(prompt.contains("原文：今天主要是把登录问题修掉然后回归一遍没问题的话明天发版"))
            XCTAssertTrue(prompt.contains("专业整理强纠错示例："))
            XCTAssertTrue(prompt.contains("输出：把 OpenType 的 hotkey 文案改一下，不要影响菜单栏。"))
            XCTAssertTrue(prompt.contains("屏幕文字，仅供纠错和专有名词参考"))
            XCTAssertTrue(prompt.contains("OpenType 设置"))
            XCTAssertTrue(prompt.contains("最近输入，仅供语境、术语、专有名词和语气参考"))
            XCTAssertTrue(prompt.contains("刚才提到了快捷键"))
            XCTAssertTrue(prompt.contains("当前输入目标"))
            XCTAssertTrue(prompt.contains("- 应用: 备忘录"))
            XCTAssertTrue(prompt.contains("- 窗口: 发布计划"))
            XCTAssertTrue(prompt.contains("光标上下文，仅用于判断"))
            XCTAssertTrue(prompt.contains("- 光标前文本:\n\(PromptTextBlock.block("我们刚才讨论到 OpenType 的"))"))
            XCTAssertTrue(prompt.contains("- 当前选中文本:\n\(PromptTextBlock.block("快捷键"))"))
            XCTAssertTrue(prompt.contains("- 光标后文本:\n\(PromptTextBlock.block("体验需要更自然。"))"))
            XCTAssertTrue(prompt.contains("不要把这些元信息或未口述的上下文写入输出"))
            XCTAssertTrue(prompt.contains("原文：嗯那个我们周四，不对，周五下午开会"))
        }
    }

    func testSystemPromptIncludesEnglishStyleScreenAndMemoryContext() {
        withCleanSettings {
            let prompt = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "professional",
                screenContext: "Meeting notes",
                memoryContext: "previous dictation",
                inputLanguage: .english
            )

            XCTAssertTrue(prompt.contains("Do not lightly polish raw ASR"))
            XCTAssertTrue(prompt.contains("Style: professional cleanup"))
            XCTAssertTrue(prompt.contains("homophones, ASR substitutions, missing words, extra words"))
            XCTAssertTrue(prompt.contains("intelligently interpret spoken formatting intent"))
            XCTAssertTrue(prompt.contains("twenty five percent to thirty percent"))
            XCTAssertTrue(prompt.contains("Output: Set the rollout to 25%-30%, and move the release window to 3 PM to 4 PM."))
            XCTAssertTrue(prompt.contains("output tags, notes, preambles, or code fences"))
            XCTAssertTrue(prompt.contains("final_text"))
            XCTAssertTrue(prompt.contains("do not force normal explanations or status updates into numbered lists"))
            XCTAssertTrue(prompt.contains("Use 1. 2. 3. only when the raw text is clearly a list"))
            XCTAssertTrue(prompt.contains("Professional cleanup examples:"))
            XCTAssertTrue(prompt.contains("Raw: today the main thing is fixing the login issue and then running regression"))
            XCTAssertTrue(prompt.contains("Strong correction examples:"))
            XCTAssertTrue(prompt.contains("Output: Update the OpenType hotkey copy, and do not affect the menu bar."))
            XCTAssertTrue(prompt.contains("On-screen text for correction and proper nouns only"))
            XCTAssertTrue(prompt.contains("Meeting notes"))
            XCTAssertTrue(prompt.contains("Recent input for context, terminology, proper nouns, and tone only"))
            XCTAssertTrue(prompt.contains("previous dictation"))
            XCTAssertTrue(prompt.contains("Raw: um we're meeting Thursday, sorry, Friday afternoon"))
        }
    }

    func testSystemPromptIncludesScreenImageContextOnlyWhenAvailable() {
        withCleanSettings {
            let withoutImage = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                inputLanguage: .chinese
            )
            XCTAssertFalse(withoutImage.contains("屏幕截图已随本次请求提供"))

            let chinese = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                screenImageAvailable: true,
                inputLanguage: .chinese
            )
            XCTAssertTrue(chinese.contains("屏幕截图已随本次请求提供"))

            let english = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                screenImageAvailable: true,
                inputLanguage: .english
            )
            XCTAssertTrue(english.contains("A screen image is attached to this request"))
        }
    }

    func testCasualStylePromptStillRequiresCorrection() {
        withCleanSettings {
            let chinese = PromptBuilder.buildSystemPrompt(
                style: .casual,
                stylePrompt: "",
                inputLanguage: .chinese
            )
            XCTAssertTrue(chinese.contains("主动修正明显错别字、同音词"))
            XCTAssertTrue(chinese.contains("不要把明显识别错误原样留下"))
            XCTAssertFalse(chinese.contains("专业整理补充示例："))

            let english = PromptBuilder.buildSystemPrompt(
                style: .casual,
                stylePrompt: "",
                inputLanguage: .english
            )
            XCTAssertTrue(english.contains("actively fix obvious typos, homophones"))
            XCTAssertTrue(english.contains("Do not leave clear ASR errors in place"))
            XCTAssertFalse(english.contains("Professional cleanup examples:"))
        }
    }

    func testCustomSystemPromptOverridesBaseAndStyleButKeepsOutputContract() {
        withCleanSettings {
            AppSettings.shared.useCustomSystemPrompt = true
            AppSettings.shared.customSystemPrompt = "Only normalize names."

            let prompt = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "ignored",
                screenContext: "visible text",
                memoryContext: "",
                inputLanguage: .english
            )

            XCTAssertTrue(prompt.hasPrefix("Only normalize names."))
            XCTAssertFalse(prompt.contains("Style: ignored"))
            XCTAssertFalse(prompt.contains("Do not lightly polish raw ASR"))
            XCTAssertTrue(prompt.contains("Input method output contract:"))
            XCTAssertTrue(prompt.contains("Prefer plain final insertable text"))
            XCTAssertTrue(prompt.contains("final_text"))
            XCTAssertTrue(prompt.contains("Do not answer the user unless"))
            XCTAssertTrue(prompt.contains("Do not add facts that are not present in the raw transcript"))
            XCTAssertTrue(prompt.contains("screen context, personal dictionary, and recent input only for corrections"))
            XCTAssertTrue(prompt.contains("visible text"))
        }
    }

    func testCommandSystemPromptUsesLanguageSpecificRules() {
        let inputContext = InputContext(
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            windowTitle: "Release reply",
            textBeforeSelection: "Hi team,",
            selectedText: "ship today",
            textAfterSelection: "Thanks.",
            outputMode: .command,
            inputLanguage: .english,
            source: .menuBar
        )
        let chinese = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "邮件正文",
            memoryContext: "上一句",
            inputLanguage: .chinese
        )
        XCTAssertTrue(chinese.contains("你是一个语音助手"))
        XCTAssertTrue(chinese.contains("以下是用户当前屏幕上的文字内容"))
        XCTAssertTrue(chinese.contains("邮件正文"))
        XCTAssertTrue(chinese.contains("以下是用户最近的输入历史，仅供语境、术语、专有名词和语气参考"))
        XCTAssertTrue(chinese.contains("输出标签、开场白、备注、引号说明或代码围栏"))
        XCTAssertTrue(chinese.contains("你只生成文本，不能真的点击、发送、删除、打开应用、按快捷键、改系统设置或执行外部动作"))
        XCTAssertTrue(chinese.contains("输出空字符串，不要声称已经完成"))
        XCTAssertTrue(chinese.contains("智能处理口述里的自我纠正、重说"))
        XCTAssertTrue(chinese.contains("除非用户明确要求 Markdown 结构"))

        let english = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "email body",
            memoryContext: "",
            inputContext: inputContext,
            inputLanguage: .english
        )
        XCTAssertTrue(english.contains("You are a voice assistant"))
        XCTAssertTrue(english.contains("On-screen text below"))
        XCTAssertTrue(english.contains("use it only for corrections, proper nouns, and context"))
        XCTAssertTrue(english.contains("email body"))
        XCTAssertTrue(english.contains("Current input target"))
        XCTAssertTrue(english.contains("- App: Mail"))
        XCTAssertTrue(english.contains("- Window: Release reply"))
        XCTAssertTrue(english.contains("cursor context for tone"))
        XCTAssertTrue(english.contains("- Text before cursor/selection:\n\(PromptTextBlock.block("Hi team,"))"))
        XCTAssertTrue(english.contains("- Selected text:\n\(PromptTextBlock.block("ship today"))"))
        XCTAssertTrue(english.contains("- Text after cursor/selection:\n\(PromptTextBlock.block("Thanks."))"))
        XCTAssertTrue(english.contains("undictated surrounding text"))
        XCTAssertTrue(english.contains("output labels, preambles, notes, quote wrappers, or code fences"))
        XCTAssertTrue(english.contains("You only generate text; you cannot actually click, send, delete, open apps, press shortcuts, change system settings, or perform external side effects"))
        XCTAssertTrue(english.contains("output an empty string and do not claim it is done"))
        XCTAssertTrue(english.contains("Intelligently handle self-corrections, restarts"))
        XCTAssertTrue(english.contains("unless the user explicitly asks for Markdown structure"))
        XCTAssertFalse(english.contains("Recent input history"))
    }

    func testCommandPromptIncludesScreenImageContextOnlyWhenAvailable() {
        let withoutImage = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "",
            inputLanguage: .chinese
        )
        XCTAssertFalse(withoutImage.contains("用户当前屏幕截图已随本次请求提供"))

        let chinese = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "",
            screenImageAvailable: true,
            inputLanguage: .chinese
        )
        XCTAssertTrue(chinese.contains("用户当前屏幕截图已随本次请求提供"))

        let english = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "",
            screenImageAvailable: true,
            inputLanguage: .english
        )
        XCTAssertTrue(english.contains("current screen image is attached"))
    }
}
