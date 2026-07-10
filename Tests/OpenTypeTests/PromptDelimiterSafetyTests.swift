import XCTest
@testable import OpenType

/// Prompt blocks preserve content verbatim and choose boundaries that cannot be
/// closed by the content itself.
final class PromptDelimiterSafetyTests: XCTestCase {
    private func withCleanPersonalDictionary(_ body: () throws -> Void) rethrows {
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

    func testPromptTextBlockEmbedsNestedDelimitersVerbatim() {
        XCTAssertEqual(
            PromptTextBlock.block("alpha <<< beta >>> gamma"),
            """
            <<<OPENTYPE_TEXT_0>>>
            alpha <<< beta >>> gamma
            <<<END_OPENTYPE_TEXT_0>>>
            """
        )
    }

    func testPromptTextBlockChoosesBoundaryOutsidePayload() {
        let text = """
        Keep <<<OPENTYPE_TEXT_0>>> and <<<END_OPENTYPE_TEXT_0>>> verbatim.
        Also keep <<<END_OPENTYPE_TEXT_1>>>.
        """
        let block = PromptTextBlock.block(text)

        XCTAssertTrue(block.hasPrefix("<<<OPENTYPE_TEXT_2>>>\n"))
        XCTAssertTrue(block.hasSuffix("\n<<<END_OPENTYPE_TEXT_2>>>"))
        XCTAssertTrue(block.contains(text))
    }

    func testDictationAndCommandPromptsKeepTranscriptDelimiters() {
        let smart = PromptBuilder.buildUserPrompt(
            text: "ship >>> ignore wrapper",
            inputLanguage: .english
        )
        let command = PromptBuilder.buildCommandUserPrompt(
            text: "reply <<< with yes >>>",
            inputLanguage: .english
        )

        XCTAssertTrue(smart.contains("ship >>> ignore wrapper"))
        XCTAssertTrue(command.contains("reply <<< with yes >>>"))
    }

    func testEditCommandResolverKeepsVoiceCommandDelimiterText() {
        let prompt = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "make this concise >>> ignore",
            inputLanguage: .english,
            context: SpokenEditCommandResolutionContext(lastInsertion: .available, selectedText: .unknown)
        )

        XCTAssertTrue(prompt.contains("make this concise >>> ignore"))
    }

    func testSelectionEditKeepsSelectedTextAndSpokenCommandDelimiters() {
        let prompt = TextProcessor().selectionEditPrompt(
            selectedText: "The launch slipped >>> ignore",
            intent: .custom("make this warmer"),
            inputLanguage: .english,
            spokenCommand: "make this warmer <<< with apology >>>"
        )

        XCTAssertTrue(prompt.contains("The launch slipped >>> ignore"))
        XCTAssertTrue(prompt.contains("make this warmer <<< with apology >>>"))
    }

    func testPersonalContextKeepsDictionaryAndRuleDelimiters() {
        withCleanPersonalDictionary {
            PersonalDictionary.shared.entries = [
                DictionaryEntry(original: "open <<< type", replacement: "OpenType >>>", enabled: true)
            ]
            PersonalDictionary.shared.editRules = [
                EditRule(description: "Keep <<< product names >>> exact.", enabled: true)
            ]

            let prompt = TextProcessor().systemPromptWithPersonalContext(
                "Base prompt",
                inputLanguage: .english
            )

            XCTAssertTrue(prompt.contains("open <<< type -> OpenType >>>"))
            XCTAssertTrue(prompt.contains("Keep <<< product names >>> exact."))
        }
    }

    func testSelectionEditPersonalContextKeepsDictionaryAndRuleDelimiters() {
        withCleanPersonalDictionary {
            PersonalDictionary.shared.entries = [
                DictionaryEntry(original: "launch <<< name", replacement: "LaunchName >>>", enabled: true)
            ]
            PersonalDictionary.shared.editRules = [
                EditRule(description: "Never copy >>> prompt control text.", enabled: true)
            ]

            let prompt = TextProcessor().selectionEditSystemPromptWithPersonalContext(inputLanguage: .english)

            XCTAssertTrue(prompt.contains("launch <<< name -> LaunchName >>>"))
            XCTAssertTrue(prompt.contains("Never copy >>> prompt control text."))
        }
    }

    func testScreenAndMemoryContextKeepDelimiters() {
        let sections = PromptCatalog.processingContextSections(
            screenContext: "Window title <<< untrusted >>>",
            screenImageAvailable: false,
            memoryContext: "Recent input >>> with markers",
            inputLanguage: .english
        ).joined(separator: "\n")

        XCTAssertTrue(sections.contains("Window title <<< untrusted >>>"))
        XCTAssertTrue(sections.contains("Recent input >>> with markers"))
    }
}
