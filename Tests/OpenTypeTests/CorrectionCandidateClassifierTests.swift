import XCTest
@testable import OpenType

final class CorrectionCandidateClassifierTests: XCTestCase {
    func testLearnsCaseAndSpacingCorrectionAsHighConfidenceTerm() throws {
        let candidate = try XCTUnwrap(CorrectionCandidateClassifier.candidate(
            inserted: "Please use open type today.",
            userFinal: "Please use OpenType today.",
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: "com.apple.Notes"
        ))

        XCTAssertEqual(candidate.original, "open type")
        XCTAssertEqual(candidate.replacement, "OpenType")
        XCTAssertGreaterThanOrEqual(candidate.confidence, 0.92)
    }

    func testLearnsOneLocalizedProductTypo() throws {
        let candidate = try XCTUnwrap(CorrectionCandidateClassifier.candidate(
            inserted: "Use OpenTape for dictation.",
            userFinal: "Use OpenType for dictation.",
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: nil
        ))

        XCTAssertEqual(candidate.original, "OpenTape")
        XCTAssertEqual(candidate.replacement, "OpenType")
    }

    func testKeepsChineseSingleCharacterCorrectionPending() throws {
        let candidate = try XCTUnwrap(CorrectionCandidateClassifier.candidate(
            inserted: "不要影响菜单蓝。",
            userFinal: "不要影响菜单栏。",
            sourceRecordID: UUID(),
            languageCode: "zh",
            bundleIdentifier: nil
        ))

        XCTAssertEqual(candidate.original, "蓝")
        XCTAssertEqual(candidate.replacement, "栏")
        XCTAssertLessThan(candidate.confidence, 0.92)
    }

    func testRejectsPunctuationAndLineBreakOnlyEdits() {
        XCTAssertNil(CorrectionCandidateClassifier.candidate(
            inserted: "Shopping list: bananas, milk.",
            userFinal: "Shopping list:\n- Bananas\n- Milk",
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: nil
        ))
    }

    func testRejectsURLAndMultipleEditHunks() {
        XCTAssertNil(CorrectionCandidateClassifier.candidate(
            inserted: "Open https://example.com/a now",
            userFinal: "Open https://example.com/b now",
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: nil
        ))
        XCTAssertNil(CorrectionCandidateClassifier.candidate(
            inserted: "alpha xx middle yy omega",
            userFinal: "alpha aa middle bb omega",
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: nil
        ))
    }

    func testDoesNotAssociatePlainContinuationWithPreviousInsertion() {
        XCTAssertNil(CorrectionObservationPolicy.associatedFinalText(
            inserted: "Original sentence.",
            edited: "Original sentence. More typing"
        ))
        XCTAssertEqual(
            CorrectionObservationPolicy.associatedFinalText(
                inserted: "Original sentence.",
                edited: "Corrected sentence."
            ),
            "Corrected sentence."
        )
    }

    func testRejectsNearTotalReplacementAsNotCorrection() {
        XCTAssertNil(CorrectionObservationPolicy.associatedFinalText(
            inserted: "我挺好奇的，这个到底是给种地产生了什么影响",
            edited: "Follow up"
        ))
        XCTAssertNil(CorrectionObservationPolicy.associatedFinalText(
            inserted: "OpenAI 的第一方声明到底在哪里",
            edited: "Follow up"
        ))
        XCTAssertNil(CorrectionObservationPolicy.associatedFinalText(
            inserted: "Hello world, how are you?",
            edited: "Something entirely different."
        ))
    }

    func testAcceptsPartialCorrectionWithSufficientOverlap() {
        XCTAssertEqual(
            CorrectionObservationPolicy.associatedFinalText(
                inserted: "不要影响菜单蓝。",
                edited: "不要影响菜单栏。"
            ),
            "不要影响菜单栏。"
        )
        XCTAssertEqual(
            CorrectionObservationPolicy.associatedFinalText(
                inserted: "Please use OpenTape for dictation.",
                edited: "Please use OpenType for dictation."
            ),
            "Please use OpenType for dictation."
        )
    }
}
