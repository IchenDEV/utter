import Foundation

package enum DeferredReplacementCopyReason: Equatable {
    case notReady
    case expired
    case missingTarget
    case appChanged
}

package enum DeferredReplacementDecision: Equatable {
    case replace
    case copy(DeferredReplacementCopyReason)
}

package enum DeferredReplacementPolicy {
    package static let expirationInterval: TimeInterval = 15

    package static func shouldUseDeferredReplacement(outputMode: OutputMode, enableInstantInsert: Bool) -> Bool {
        outputMode == .processed && enableInstantInsert
    }

    package static func decision(
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
