import XCTest
@testable import UtterProcessing

final class TranslationLanguageSampleTests: XCTestCase {
    func testIgnoresProtectedValuesWithoutMutatingTheCandidate() {
        let text = "Please deploy Redis at https://example.com on Friday at 3:30."
        let sample = TranslationLanguageSample.prepare(text, knownTerms: ["Redis"])
        XCTAssertTrue(sample.contains("Please deploy"))
        XCTAssertFalse(sample.contains("Redis"))
        XCTAssertFalse(sample.contains("example.com"))
        XCTAssertFalse(sample.contains("3:30"))
        XCTAssertTrue(TranslationLanguageSample.hasLinguisticContent(sample))
        XCTAssertTrue(text.contains("Redis"))
    }

    func testNumbersCodeAndTermsAloneAreUnverifiable() {
        for text in ["123", "三件", "https://example.com", "`return value`", "```swift\nlet x = 3\n```",
                     "Kubernetes Redis", "API HTTP", "getUserName", "Hi"] {
            let sample = TranslationLanguageSample.prepare(text, knownTerms: ["Kubernetes", "Redis"])
            XCTAssertFalse(TranslationLanguageSample.hasLinguisticContent(sample), text)
        }
    }

    func testChineseAndOrdinaryLatinSentencesRemainClassifiable() {
        for text in ["我们明天下午开会。", "We will meet tomorrow afternoon.", "Buenos días."] {
            XCTAssertTrue(TranslationLanguageSample.hasLinguisticContent(TranslationLanguageSample.prepare(text)))
        }
    }

    func testTermsUseWordBoundariesAndDoNotHideOtherWords() {
        let sample = TranslationLanguageSample.prepare("This is a redirection message.", knownTerms: ["red"])
        XCTAssertTrue(sample.contains("redirection"))
    }
}
