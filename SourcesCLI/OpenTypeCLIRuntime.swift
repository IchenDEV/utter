import AppKit
import Foundation

struct DeveloperInterfaceConfig {
    let enabled: Bool
    let port: Int
    let token: String

    static func load() throws -> DeveloperInterfaceConfig {
        guard let defaults = UserDefaults(suiteName: OpenTypeLauncher.bundleIdentifier) else {
            throw CLIError("cannot read Utter preferences")
        }
        let enabled = defaults.object(forKey: "developerInterfaceEnabled") as? Bool ?? false
        guard enabled else {
            throw CLIError("developer interface is disabled")
        }
        let port = defaults.integer(forKey: "developerHTTPPort")
        let token = defaults.string(forKey: "developerHTTPToken") ?? ""
        guard (1...65_535).contains(port), !token.isEmpty else {
            throw CLIError("developer interface is not configured")
        }
        return DeveloperInterfaceConfig(enabled: enabled, port: port, token: token)
    }
}

enum OpenTypeLauncher {
    static let bundleIdentifier = "com.opentype.voiceinput"

    static func launchIfNeeded() async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            return
        }
        guard let appURL = findAppURL() else {
            throw CLIError("Utter.app was not found")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        try await Task.sleep(nanoseconds: 700_000_000)
    }

    private static func findAppURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["OPENTYPE_APP_PATH"] {
            return URL(fileURLWithPath: path)
        }
        if let bundled = bundledAppURL() {
            return bundled
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications/Utter.app",
            "\(home)/Applications/Utter.app",
            "/Applications/OpenType.app",
            "\(home)/Applications/OpenType.app"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func bundledAppURL() -> URL? {
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}

enum CLIIdentity {
    static var clientID: String {
        let encoded = Data(executablePath.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "cli:\(encoded)"
    }

    private static var executablePath: String {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
