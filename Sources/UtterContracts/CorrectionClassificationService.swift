import Foundation
import UtterRuntime

package protocol CorrectionClassificationService: Sendable {
    func associatedFinalText(inserted: String, edited: String) -> String?
    func candidate(inserted: String, userFinal: String, sourceRecordID: UUID,
                   languageCode: String?, bundleIdentifier: String?) -> LearnedCorrectionCandidate?
}

extension DataServices {
    package static let correctionClassification = ServiceKey<any CorrectionClassificationService>("data.correction-classification")
}
