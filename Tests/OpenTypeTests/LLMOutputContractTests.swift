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
import UtterContracts
import XCTest
@testable import UtterPresentation

final class LLMOutputContractTests: XCTestCase {
    func testVoiceCommandPromptsAdvertiseFinalTextJSONContract() {
        for language in InputLanguage.allCases {
            let prompt = PromptBuilder.buildCommandSystemPrompt(
                screenContext: "",
                inputLanguage: language
            )

            XCTAssertTrue(prompt.contains("final_text"), "\(language)")
        }
    }

    func testSelectionEditPromptsAdvertiseFinalTextJSONContract() {
        let processor = TextProcessor()
        for language in InputLanguage.allCases {
            let prompt = SelectionEditRecipe.selectionEditSystemPrompt(inputLanguage: language)

            XCTAssertTrue(prompt.contains("final_text"), "\(language)")
        }
    }

    func testVoiceCommandOutputDoesNotMineEmbeddedFinalText() {
        let processor = TextProcessor()
        let output = """
        I will use the requested format:
        {"final_text":"Sounds good, I will send the release notes today.","reason":"reply"}
        """

        XCTAssertEqual(
            processor.cleanCommandGeneratedOutput(output, inputLanguage: .english),
            output
        )
    }

    func testSelectionEditOutputExtractsWrappedFinalText() {
        let processor = TextProcessor()
        let output = """
        {"final_text":"Please send the release notes today.","reason":"made it formal"}
        """

        XCTAssertEqual(
            SelectionEditRecipe.normalize(output),
            "Please send the release notes today."
        )
    }

    func testSelectionEditKeepsEmbeddedFinalTextExample() {
        let processor = TextProcessor()
        let output = #"Document this example: {"final_text":"hello"}."#

        XCTAssertEqual(
            SelectionEditRecipe.normalize(output),
            output
        )
    }
}
