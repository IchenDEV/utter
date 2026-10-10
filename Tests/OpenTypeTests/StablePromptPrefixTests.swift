import UtterMediaContracts
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
import UtterPresentationContracts
import UtterContracts
import XCTest
@testable import UtterPresentation

@MainActor
final class StablePromptPrefixTests: XCTestCase {
    func testFormattingAssemblyReproducesLegacySystemPrompt() {
        let assembly = PromptBuilder.buildFormattingAssembly(
            style: .professional,
            stylePrompt: "",
            screenContext: "screen text",
            screenImageAvailable: false,
            memoryContext: "recent input",
            inputContext: nil,
            formatKind: .plainParagraph,
            inputLanguage: .chinese,
            useCustomSystemPrompt: false,
            customSystemPrompt: ""
        )
        let legacy = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            screenContext: "screen text",
            screenImageAvailable: false,
            memoryContext: "recent input",
            inputContext: nil,
            formatKind: .plainParagraph,
            inputLanguage: .chinese,
            useCustomSystemPrompt: false,
            customSystemPrompt: ""
        )
        XCTAssertEqual(assembly.systemPrompt, legacy)
    }

    func testStablePrefixIgnoresVolatileContext() {
        let first = PromptBuilder.buildFormattingAssembly(
            style: .professional,
            stylePrompt: "",
            screenContext: "SCREEN_ONE",
            memoryContext: "MEMORY_ONE",
            inputLanguage: .chinese,
            useCustomSystemPrompt: false,
            customSystemPrompt: ""
        )
        let second = PromptBuilder.buildFormattingAssembly(
            style: .professional,
            stylePrompt: "",
            screenContext: "SCREEN_TWO",
            memoryContext: "MEMORY_TWO",
            inputLanguage: .chinese,
            useCustomSystemPrompt: false,
            customSystemPrompt: ""
        )

        XCTAssertEqual(first.stablePrefix, second.stablePrefix)
        XCTAssertNotEqual(first.volatileContext, second.volatileContext)
        XCTAssertTrue(first.volatileContext.contains("SCREEN_ONE"))
        XCTAssertTrue(first.volatileContext.contains("MEMORY_ONE"))
        XCTAssertFalse(first.stablePrefix.contains("SCREEN_ONE"))
        XCTAssertFalse(first.stablePrefix.contains("MEMORY_ONE"))
    }

    func testStablePrefixDropsRuntimeTimestamp() {
        let assembly = PromptBuilder.buildFormattingAssembly(
            style: .professional,
            stylePrompt: "",
            inputLanguage: .chinese,
            useCustomSystemPrompt: false,
            customSystemPrompt: ""
        )
        XCTAssertTrue(assembly.volatileContext.contains("当前时间"))
        XCTAssertFalse(assembly.stablePrefix.contains("当前时间"))
    }

    func testPersonalContextMovesToVolatileUserTurn() {
        let snapshot = PersonalDictionarySnapshot(
            entries: [DictionaryEntry(original: "open type", replacement: "OpenType")],
            editRules: [EditRule(description: "Keep product names exact.")]
        )
        let options = TextProcessingOptions(settings: AppSettings.shared)
        let assembly = TextProcessor().formattingAssembly(
            options: options,
            screenContext: "SCREEN_ONLY",
            screenImageAvailable: false,
            memoryContext: "MEMORY_ONLY",
            inputContext: nil,
            dictionarySnapshot: snapshot,
            transcript: "open type"
        )

        XCTAssertFalse(assembly.stablePrefix.contains("open type -> OpenType"))
        XCTAssertFalse(assembly.stablePrefix.contains("Keep product names exact."))
        XCTAssertFalse(assembly.stablePrefix.contains("SCREEN_ONLY"))
        XCTAssertTrue(assembly.volatileContext.contains("open type -> OpenType"))
        XCTAssertTrue(assembly.volatileContext.contains("Keep product names exact."))

        let userPrompt = assembly.userPrompt(containing: "USER_PAYLOAD")
        XCTAssertTrue(userPrompt.hasPrefix(assembly.volatileContext))
        XCTAssertTrue(userPrompt.hasSuffix("USER_PAYLOAD"))
    }
}
