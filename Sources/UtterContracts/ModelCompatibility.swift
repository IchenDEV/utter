import Foundation

package enum ModelCompatibility: Equatable, Sendable {
    case compatible
    case marginal(String)
    case incompatible(String)
}

extension ModelCompatibility {
    package var isCompatible: Bool {
        if case .compatible = self { return true }
        return false
    }

    package var isMarginal: Bool {
        if case .marginal = self { return true }
        return false
    }

    package var isIncompatible: Bool {
        if case .incompatible = self { return true }
        return false
    }

    package var message: String? {
        switch self {
        case .compatible: return nil
        case .marginal(let msg), .incompatible(let msg): return msg
        }
    }
}
