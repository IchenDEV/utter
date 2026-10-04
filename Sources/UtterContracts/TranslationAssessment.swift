import Foundation

package struct TranslationAssessment: Codable, Equatable, Sendable {
    package enum Status: String, Codable, Sendable { case confirmed, wrongLanguage, unverifiable }
    package let target: TranslationLanguage
    package let status: Status
    package let targetConfidence: Double?
    package let otherConfidence: Double?

    package func confirms(_ language: TranslationLanguage) -> Bool {
        target == language && status == .confirmed
    }

    package static func assess(target: TranslationLanguage, hasLinguisticContent: Bool,
                               scores: [String: Double]) -> Self {
        guard hasLinguisticContent, !scores.isEmpty,
              scores.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return Self(target: target, status: .unverifiable, targetConfidence: nil, otherConfidence: nil)
        }
        let confidence = scores[target.rawValue] ?? 0
        let other = scores.filter { $0.key != target.rawValue }.values.max() ?? 0
        let status: Status
        if confidence >= 0.7, confidence - other >= 0.2 - 1e-12 {
            status = .confirmed
        } else if other >= 0.7, other - confidence >= 0.2 - 1e-12 {
            status = .wrongLanguage
        } else { status = .unverifiable }
        return Self(target: target, status: status, targetConfidence: confidence, otherConfidence: other)
    }
}
