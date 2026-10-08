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
import XCTest
import UtterContracts
import UtterProcessing

final class TranslationLanguageRecognitionTests: XCTestCase {
    func testRecognizesEnglishWithoutSourceLanguageAssumptions() {
        let text = "We have completed the review and will discuss the remaining work at our meeting tomorrow afternoon."
        XCTAssertEqual(TranslationLanguageRecognition.assess(text, target: .english).status, .confirmed)
        XCTAssertEqual(TranslationLanguageRecognition.assess(text, target: .korean).status, .wrongLanguage)
    }

    func testRecognizesChineseBodyWithEnglishTerms() {
        let text = "我们已经完成了项目检查，明天下午将在会议上讨论剩下的工作，请提前准备好相关资料。Redis Kubernetes"
        XCTAssertEqual(TranslationLanguageRecognition.assess(text, target: .simplifiedChinese,
            knownTerms: ["Redis", "Kubernetes"]).status, .confirmed)
    }

    func testNonLinguisticValuesAndShortGreetingsRemainUnverifiable() {
        for text in ["123", "https://example.com", "`return value`", "API HTTP", "John Smith", "Hi"] {
            XCTAssertEqual(TranslationLanguageRecognition.assess(text, target: .english).status, .unverifiable, text)
        }
    }
}
