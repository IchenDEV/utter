import Foundation
import XCTest
@testable import UtterContracts

final class TranslationAssessmentTests: XCTestCase {
    func testConfirmationRequiresBothConfidenceAndMargin() {
        let cases: [([String: Double], TranslationAssessment.Status)] = [
            (["en": 0.7, "de": 0.3], .confirmed),
            (["en": 0.7, "de": 0.5], .confirmed),
            (["en": 0.699, "de": 0.1], .unverifiable),
            (["en": 0.7, "de": 0.501], .unverifiable),
            (["en": 0.1, "de": 0.9], .wrongLanguage),
            ([:], .unverifiable),
            (["en": .nan], .unverifiable),
            (["en": 1.1], .unverifiable),
        ]
        for (scores, expected) in cases {
            XCTAssertEqual(TranslationAssessment.assess(target: .english,
                hasLinguisticContent: true, scores: scores).status, expected)
        }
    }

    func testNonLinguisticOutputCannotBeConfirmedOrMarkedWrong() {
        for scores in [["en": 1.0], ["de": 1.0]] {
            let result = TranslationAssessment.assess(target: .english,
                hasLinguisticContent: false, scores: scores)
            XCTAssertEqual(result.status, .unverifiable)
        }
    }

    func testChineseScriptAndFrozenTargetAreRetained() throws {
        let result = TranslationAssessment.assess(target: .traditionalChinese,
            hasLinguisticContent: true, scores: ["zh-Hant": 0.9, "zh-Hans": 0.1])
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.target, .traditionalChinese)
        XCTAssertFalse(result.confirms(.simplifiedChinese))
        let data = try JSONEncoder().encode(ProcessingDecision(.accepted, translation: result))
        XCTAssertEqual(try JSONDecoder().decode(ProcessingDecision.self, from: data).translation, result)
    }

    func testLegacyDecisionRemainsReadableButHasNoTranslationProof() throws {
        let result = try JSONDecoder().decode(ProcessingDecision.self,
            from: Data(#"{"disposition":"accepted"}"#.utf8))
        XCTAssertNil(result.translation)
    }
}
