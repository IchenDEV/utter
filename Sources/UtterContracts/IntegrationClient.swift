import Foundation

package struct IntegrationClient: Codable, Equatable, Identifiable {
    package enum Transport: String, Codable, Equatable {
        case http
        case xpc
        case cli
    }

    package enum Capability: String, Codable, Equatable, Hashable {
        case record
        case streamEvents
        case provideAudio
        case manageClients
    }

    package let id: String
    package var displayName: String
    package var bundleIdentifier: String?
    package var teamIdentifier: String?
    package var codeRequirement: String?
    package var transport: Transport
    package var capabilities: Set<Capability>
    package var firstApprovedAt: Date
    package var lastUsedAt: Date?

    package static func localHTTP(tokenID: String) -> IntegrationClient {
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

    package static func localCLI(executablePath: String) -> IntegrationClient {
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

    package static func registeredApp(
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

    package init(id: String, displayName: String, bundleIdentifier: String? = nil, teamIdentifier: String? = nil, codeRequirement: String? = nil, transport: Transport, capabilities: Set<Capability>, firstApprovedAt: Date, lastUsedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.codeRequirement = codeRequirement
        self.transport = transport
        self.capabilities = capabilities
        self.firstApprovedAt = firstApprovedAt
        self.lastUsedAt = lastUsedAt
    }
}
