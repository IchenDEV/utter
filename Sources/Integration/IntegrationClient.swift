import Foundation

struct IntegrationClient: Codable, Equatable, Identifiable {
    enum Transport: String, Codable, Equatable {
        case http
        case xpc
        case cli
    }

    enum Capability: String, Codable, Equatable, Hashable {
        case record
        case streamEvents
        case provideAudio
        case manageClients
    }

    let id: String
    var displayName: String
    var bundleIdentifier: String?
    var teamIdentifier: String?
    var codeRequirement: String?
    var transport: Transport
    var capabilities: Set<Capability>
    var firstApprovedAt: Date
    var lastUsedAt: Date?

    static func localHTTP(tokenID: String) -> IntegrationClient {
        IntegrationClient(
            id: "http:\(tokenID)",
            displayName: "Local HTTP",
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: nil,
            transport: .http,
            capabilities: [.record, .streamEvents],
            firstApprovedAt: Date(),
            lastUsedAt: nil
        )
    }

    static func localCLI(executablePath: String) -> IntegrationClient {
        IntegrationClient(
            id: stableID(prefix: "cli", value: executablePath),
            displayName: "Utter CLI",
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: executablePath,
            transport: .cli,
            capabilities: [.record, .streamEvents],
            firstApprovedAt: Date(),
            lastUsedAt: nil
        )
    }

    static func registeredApp(
        displayName: String,
        bundleIdentifier: String?,
        teamIdentifier: String?,
        codeRequirement: String?,
        transport: Transport
    ) -> IntegrationClient {
        let identity = bundleIdentifier ?? codeRequirement ?? displayName
        return IntegrationClient(
            id: stableID(prefix: transport.rawValue, value: identity),
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier,
            codeRequirement: codeRequirement,
            transport: transport,
            capabilities: [.record, .streamEvents],
            firstApprovedAt: Date(),
            lastUsedAt: nil
        )
    }

    private static func stableID(prefix: String, value: String) -> String {
        let encoded = Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(prefix):\(encoded)"
    }
}
