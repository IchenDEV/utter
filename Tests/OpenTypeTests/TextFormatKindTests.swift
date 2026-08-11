import XCTest
@testable import OpenType

final class TextFormatKindTests: XCTestCase {
    func testSeparatesUnorderedListFromOrderedSteps() {
        XCTAssertEqual(
            TextFormatClassifier.classify(
                text: "购物清单，香蕉，燕麦奶，黑巧克力",
                context: nil
            ).kind,
            .unorderedList
        )
        XCTAssertEqual(
            TextFormatClassifier.classify(
                text: "第一确认需求，第二排期，第三更新预算",
                context: nil
            ).kind,
            .orderedSteps
        )
    }

    func testRecognizesEmailStructureAndAppPriors() {
        XCTAssertEqual(
            TextFormatClassifier.classify(
                text: "Hi Anna, call me tomorrow. Thanks, Jack.",
                context: nil
            ).kind,
            .email
        )
        let slack = InputContext(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )
        XCTAssertEqual(
            TextFormatClassifier.classify(text: "the build is ready", context: slack).kind,
            .chat
        )
    }

    func testExplicitListBeatsMailApplicationPrior() {
        let mail = InputContext(
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            outputMode: .processed,
            inputLanguage: .chinese,
            source: .menuBar
        )
        XCTAssertEqual(
            TextFormatClassifier.classify(text: "待办清单，修复登录，更新文档", context: mail).kind,
            .unorderedList
        )
    }

    func testCodeApplicationSafetyBeatsFormattingIntent() {
        let terminal = InputContext(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            outputMode: .processed,
            inputLanguage: .english,
            source: .menuBar
        )
        XCTAssertEqual(
            TextFormatClassifier.classify(
                text: "first run git status second run swift test",
                context: terminal
            ).kind,
            .codeOrTerminal
        )
    }

    func testFormatContractIsExplicitInPrompt() {
        let prompt = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            formatKind: .unorderedList,
            inputLanguage: .chinese,
            useCustomSystemPrompt: false,
            customSystemPrompt: ""
        )

        XCTAssertTrue(prompt.contains("本次已判定的输出类型：unorderedList"))
        XCTAssertTrue(prompt.contains("使用“- ”"))
        XCTAssertTrue(prompt.contains("绝对不要改成编号步骤"))
    }
}
