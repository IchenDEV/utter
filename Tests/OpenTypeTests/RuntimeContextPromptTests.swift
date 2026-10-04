import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterProcessing
import XCTest
@testable import UtterPresentation

final class RuntimeContextPromptTests: XCTestCase {
    func testRuntimeContextUsesFixedDateAndTimezoneForLLMOnly() {
        let date = Date(timeIntervalSince1970: 0)
        let timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!

        let chinese = PromptCatalog.runtimeContextSection(
            now: date,
            timeZone: timeZone,
            inputLanguage: .chinese
        )
        let english = PromptCatalog.runtimeContextSection(
            now: date,
            timeZone: timeZone,
            inputLanguage: .english
        )

        XCTAssertTrue(chinese.contains("当前时间"))
        XCTAssertTrue(chinese.contains("相对时间表达"))
        XCTAssertTrue(chinese.contains("除非用户明确要求具体日期"))
        XCTAssertTrue(chinese.contains("1970-01-01 08:00 UTC+08:00"))
        XCTAssertTrue(english.contains("Current time for relative time references only"))
        XCTAssertTrue(english.contains("unless the user explicitly asks"))
        XCTAssertTrue(english.contains("1970-01-01 08:00 UTC+08:00"))
    }

    func testProcessingCommandAndSelectionPromptsIncludeRuntimeContext() {
        let processing = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            inputLanguage: .chinese
        )
        let command = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "",
            inputLanguage: .english
        )
        let selection = TextProcessor().selectionEditPrompt(
            selectedText: "ship tomorrow",
            intent: .formal,
            inputLanguage: .english
        )

        XCTAssertTrue(processing.contains("当前时间"))
        XCTAssertTrue(command.contains("Current time for relative time references only"))
        XCTAssertTrue(selection.contains("Current time for relative time references only"))
    }
}
