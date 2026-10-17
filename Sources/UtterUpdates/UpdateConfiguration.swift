import Foundation
import UtterContracts

/// What the host bundle declares, gathered by native code so the gate itself stays pure.
package struct UpdateEnvironment: Equatable, Sendable {
    package var isApplicationBundle: Bool
    package var isAdHocSigned: Bool
    package var feedURL: String?
    package var publicKey: String?

    package init(isApplicationBundle: Bool, isAdHocSigned: Bool, feedURL: String?, publicKey: String?) {
        self.isApplicationBundle = isApplicationBundle
        self.isAdHocSigned = isAdHocSigned
        self.feedURL = feedURL
        self.publicKey = publicKey
    }
}

package struct UpdateConfiguration: Equatable, Sendable {
    package enum Resolution: Equatable, Sendable {
        case enabled(UpdateConfiguration)
        case unavailable(UpdateUnavailableReason)
    }

    package let feedURL: URL
    package let publicKey: String

    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
    private static let publicKeyByteCount = 32

    /// The updater exists only when every precondition holds. Anything else leaves it
    /// absent so a development, pull-request, or manual build performs no network activity.
    package static func resolve(_ environment: UpdateEnvironment) -> Resolution {
        guard environment.isApplicationBundle else { return .unavailable(.notApplicationBundle) }
        guard let rawFeed = environment.feedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawFeed.isEmpty else { return .unavailable(.missingFeed) }
        guard let feed = secureFeedURL(rawFeed) else { return .unavailable(.insecureFeed) }
        guard let key = environment.publicKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidPublicKey(key) else { return .unavailable(.invalidPublicKey) }
        guard !environment.isAdHocSigned else { return .unavailable(.adHocSigned) }
        return .enabled(UpdateConfiguration(feedURL: feed, publicKey: key))
    }

    static func secureFeedURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", loopbackHosts.contains(host.lowercased()) { return url }
        return nil
    }

    static func isValidPublicKey(_ key: String) -> Bool {
        Data(base64Encoded: key)?.count == publicKeyByteCount
    }
}
