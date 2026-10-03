import UtterProcessing
import UtterPresentationContracts
import XCTest
@testable import OpenType

final class MemoryContextFactBoundaryTests: XCTestCase {
    func testSmartFormatMemoryContextDoesNotBecomeFactSource() {
        let chinese = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            memoryContext: "上一句说周五发版",
            inputLanguage: .chinese
        )
        let english = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            memoryContext: "previously mentioned Friday release",
            inputLanguage: .english
        )

        XCTAssertTrue(chinese.contains("不要把这里的新事实加入输出"))
        XCTAssertTrue(english.contains("Do not add new facts from it"))
    }

    func testCommandMemoryContextRequiresCurrentVoiceCommandToReuseFacts() {
        let chinese = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "",
            memoryContext: "上一句说周五发版",
            inputLanguage: .chinese
        )
        let english = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "",
            memoryContext: "previously mentioned Friday release",
            inputLanguage: .english
        )

        XCTAssertTrue(chinese.contains("除非本次语音指令明确要求使用最近输入"))
        XCTAssertTrue(chinese.contains("不要把这里的新事实加入输出"))
        XCTAssertTrue(english.contains("unless the current voice command explicitly asks"))
        XCTAssertTrue(english.contains("Do not add facts from it"))
    }

    func testCommandScreenContextRequiresCurrentVoiceCommandToUseFacts() {
        let chinese = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "屏幕上写着周五发版",
            memoryContext: "",
            inputLanguage: .chinese
        )
        let english = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "screen says Friday release",
            screenImageAvailable: true,
            memoryContext: "",
            inputLanguage: .english
        )

        XCTAssertTrue(chinese.contains("默认仅用于纠错、专有名词和理解上下文"))
        XCTAssertTrue(chinese.contains("只有本次语音指令明确要求回复、总结、翻译、解释或使用可见屏幕内容"))
        XCTAssertTrue(english.contains("By default, use it only for corrections, proper nouns, and context"))
        XCTAssertTrue(english.contains("only when the current voice command explicitly asks"))
        XCTAssertTrue(english.contains("use it as a source of facts only when the command asks"))
    }

    @MainActor
    func testCustomSystemPromptDoesNotPromoteContextToFactSource() {
        let savedUseCustomSystemPrompt = AppSettings.shared.useCustomSystemPrompt
        let savedCustomSystemPrompt = AppSettings.shared.customSystemPrompt
        defer {
            AppSettings.shared.useCustomSystemPrompt = savedUseCustomSystemPrompt
            AppSettings.shared.customSystemPrompt = savedCustomSystemPrompt
        }

        AppSettings.shared.useCustomSystemPrompt = true
        AppSettings.shared.customSystemPrompt = "Make this concise."

        let prompt = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            screenContext: "screen-only launch date",
            memoryContext: "memory-only launch date",
            inputLanguage: .english
        )

        XCTAssertTrue(prompt.contains("Do not add facts that are not present in the raw transcript"))
        XCTAssertTrue(prompt.contains("screen context, personal dictionary, and recent input only for corrections"))
        let legacyFactSourceList = [
            "raw transcript",
            "screen context",
            "personal dictionary",
            "or recent input",
        ].joined(separator: ", ")
        XCTAssertFalse(prompt.contains(legacyFactSourceList))
    }
}
