import Foundation

enum VolcASRModel: String, CaseIterable, Identifiable {
    case seedASR2 = "volc.seedasr.sauc.duration"
    case bigASR1 = "volc.bigasr.sauc.duration"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .seedASR2: return L("volc.model.seed_asr_2")
        case .bigASR1: return L("volc.model.big_asr_1")
        }
    }

    static let recommended = VolcASRModel.seedASR2
}
