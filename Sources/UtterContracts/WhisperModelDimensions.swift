import Foundation

package enum WhisperModelDimensions {
    package static func supports(repository: String, logits: Int, encoder: Int) -> Bool {
        let variant = WhisperModelSelection.canonicalVariant(repository)
        let english = variant.hasSuffix(".en")
        let expectedLogits = english ? 51864 : variant == "large-v3" ? 51866 : 51865
        let expectedEncoder: Int
        switch variant.replacingOccurrences(of: ".en", with: "") {
        case "tiny": expectedEncoder = 384
        case "base": expectedEncoder = 512
        case "small": expectedEncoder = 768
        case "medium": expectedEncoder = 1024
        case "large", "large-v2", "large-v3": expectedEncoder = 1280
        default: return false
        }
        return logits == expectedLogits && encoder == expectedEncoder
    }
}
