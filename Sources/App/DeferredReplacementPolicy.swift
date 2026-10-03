import UtterContracts
import Foundation

enum DeferredReplacementCopyReason: Equatable {
    case notReady
    case expired
    case missingTarget
    case appChanged
}

enum DeferredReplacementDecision: Equatable {
    case replace
    case copy(DeferredReplacementCopyReason)
}

enum DeferredReplacementPolicy {
    static let expirationInterval: TimeInterval = 15

    static func shouldUseDeferredReplacement(outputMode: OutputMode, enableInstantInsert: Bool) -> Bool {
        outputMode == .processed && enableInstantInsert
    }

    static func decision(
        for replacement: DeferredReplacement,
        currentBundleIdentifier: String?,
        now: Date = Date()
    ) -> DeferredReplacementDecision {
        guard replacement.hasFormattedText else {
            return .copy(.notReady)
        }
        guard replacement.state != .expired, now < replacement.expiresAt else {
            return .copy(.expired)
        }
        guard replacement.state == .ready else {
            return .copy(.notReady)
        }
        guard let targetBundleIdentifier = replacement.targetBundleIdentifier else {
            return .copy(.missingTarget)
        }
        guard currentBundleIdentifier == targetBundleIdentifier else {
            return .copy(.appChanged)
        }
        return .replace
    }
}
