import XCTest
@testable import OpenType

@MainActor
final class ASRQualityPromptTests: XCTestCase {
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

    func testDefaultSmartFormatPromptsIncludeASRQualityRules() {
        withDefaultPromptSettings {
            let chinese = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                inputLanguage: .chinese
            )
            let english = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                inputLanguage: .english
            )

            XCTAssertTrue(chinese.contains("ASR 质量规则："))
            XCTAssertTrue(chinese.contains("模型幻听和模板尾巴"))
            XCTAssertTrue(chinese.contains("谢谢观看"))
            XCTAssertTrue(chinese.contains("逗号、句号、问号、换行"))
            XCTAssertTrue(chinese.contains("Utter、hotkey、menu bar、API、JSON、i18n、URL"))

            XCTAssertTrue(english.contains("ASR quality rules:"))
            XCTAssertTrue(english.contains("model hallucinations or template tails"))
            XCTAssertTrue(english.contains("thank you for watching"))
            XCTAssertTrue(english.contains("comma, period, question mark, new line"))
            XCTAssertTrue(english.contains("Utter, hotkey, menu bar, API, JSON, i18n, and URL"))
        }
    }
}
