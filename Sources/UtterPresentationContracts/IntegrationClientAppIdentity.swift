import UtterContracts
import Foundation
#if canImport(AppKit)
import AppKit
#endif

extension IntegrationClient {
    #if canImport(AppKit)
    package static func appIdentity(for app: NSRunningApplication, transport: Transport) -> IntegrationClient {
        let displayName = app.localizedName ?? app.bundleIdentifier ?? "Local App"
        let codeIdentity = app.executableURL?.path
        return registeredApp(
            displayName: displayName,
            bundleIdentifier: app.bundleIdentifier,
            teamIdentifier: nil,
            codeRequirement: codeIdentity,
            transport: transport
        )
    }
    #endif

    package static func appIdentity(url: URL, transport: Transport) -> IntegrationClient {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return registeredApp(
            displayName: displayName,
            bundleIdentifier: bundle?.bundleIdentifier,
            teamIdentifier: nil,
            codeRequirement: url.path,
            transport: transport
        )
    }
}
