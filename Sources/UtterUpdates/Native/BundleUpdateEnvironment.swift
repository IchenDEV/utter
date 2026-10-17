import Foundation
import Security

enum BundleUpdateEnvironment {
    static func current(bundle: Bundle = .main) -> UpdateEnvironment {
        let info = bundle.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String
        return UpdateEnvironment(
            isApplicationBundle: bundle.bundleURL.pathExtension == "app",
            isAdHocSigned: feed == nil ? false : !hasIdentitySignature(bundle.bundleURL),
            feedURL: feed,
            publicKey: info["SUPublicEDKey"] as? String)
    }

    /// An unsigned or ad-hoc bundle has no identity to anchor a trusted update to.
    static func hasIdentitySignature(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let values = information as? [String: Any],
              let rawFlags = (values[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value else { return false }
        return rawFlags & SecCodeSignatureFlags.adhoc.rawValue == 0
    }
}
