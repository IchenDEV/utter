import Foundation
import UtterContracts

package struct BuiltinCorrectionClassification: CorrectionClassificationService {
    package init() {}

    package func associatedFinalText(inserted: String, edited: String) -> String? {
        CorrectionObservationPolicy.associatedFinalText(inserted: inserted, edited: edited)
    }

    package func candidate(inserted: String, userFinal: String, sourceRecordID: UUID,
                          languageCode: String?, bundleIdentifier: String?) -> LearnedCorrectionCandidate? {
        CorrectionCandidateClassifier.candidate(
            inserted: inserted, userFinal: userFinal, sourceRecordID: sourceRecordID,
            languageCode: languageCode, bundleIdentifier: bundleIdentifier
        )
    }
}
