import Foundation

package enum CorrectionCapturePrivacyPolicy {
    private static let blockedApps = [
        "terminal", "iterm", "warp", "ghostty", "alacritty", "wezterm",
        "keychain", "1password", "bitwarden", "keepass",
    ]
    private static let blockedFieldHints = [
        "address bar", "address and search", "omnibox", "url field", "password", "secure",
    ]

    package static func isBlocked(appText: String, fieldText: String) -> Bool {
        let normalizedApp = appText.lowercased()
        let normalizedField = fieldText.lowercased()
        return blockedApps.contains(where: normalizedApp.contains)
            || blockedFieldHints.contains(where: normalizedField.contains)
    }
}
