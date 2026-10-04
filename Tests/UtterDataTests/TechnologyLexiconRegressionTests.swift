import UtterContracts
import XCTest
@testable import UtterData

final class TechnologyLexiconRegressionTests: XCTestCase {
    func testDemoTermsHaveCanonicalRecognitionAndExplicitCorrectionEvidence() {
        let lexicon = IndustryLexiconCatalog.shared.snapshot(for: .technology)
        XCTAssertTrue(lexicon.recognitionPhrases.contains("Kubernetes"))
        XCTAssertTrue(lexicon.recognitionPhrases.contains("Redis"))
        let snapshot = PersonalDictionarySnapshot(entries: [], editRules: [], industryLexicon: lexicon)
        XCTAssertEqual(snapshot.applyReplacements(to: "库伯内提斯使用 Redis"), "Kubernetes使用 Redis")
        XCTAssertTrue(snapshot.protectedTerms.contains("Kubernetes"))
        XCTAssertTrue(snapshot.protectedTerms.contains("Redis"))
    }

    func testPersonalCorrectionWinsAndUnrelatedTextDoesNotAcquireTerms() {
        let snapshot = PersonalDictionarySnapshot(entries: [DictionaryEntry(original: "库伯内提斯", replacement: "内部平台")],
            editRules: [], industryLexicon: IndustryLexiconCatalog.shared.snapshot(for: .technology))
        XCTAssertEqual(snapshot.applyReplacements(to: "库伯内提斯"), "内部平台")
        XCTAssertEqual(snapshot.applyReplacements(to: "今天讨论三件事"), "今天讨论三件事")
        XCTAssertLessThanOrEqual(snapshot.recognitionPhrases.count, SpeechRecognitionContext.maximumPhraseCount)
    }
}
