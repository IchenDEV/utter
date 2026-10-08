import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterSession

extension OpenTypeServiceTests {
    var clientID: String {
        IntegrationClient.localHTTP(tokenID: "token").id
    }

    var otherClientID: String {
        IntegrationClient.localHTTP(tokenID: "other").id
    }

    var recordOnlyClient: IntegrationClient {
        IntegrationClient(
            id: "http:record-only",
            displayName: "Record Only",
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: nil,
            transport: .http,
            capabilities: [.record],
            firstApprovedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: nil
        )
    }

    func makeService(registry: IntegrationClientRegistry) -> OpenTypeService {
        OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token"),
            registry: registry
        )
    }

    func request() -> InputSessionRequest {
        InputSessionRequest(mode: .processed, language: .english, useScreenContext: false)
    }

    func approveLocalHTTP(in registry: IntegrationClientRegistry) {
        registry.approve(IntegrationClient.localHTTP(tokenID: "token"))
    }

    func approveOtherLocalHTTP(in registry: IntegrationClientRegistry) {
        registry.approve(IntegrationClient.localHTTP(tokenID: "other"))
    }

    func registry() -> RegistryStore {
        let suiteName = "OpenTypeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RegistryStore(
            registry: IntegrationClientRegistry(defaults: defaults, reportError: { _ in }),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    func assertThrowsIntegrationError(
        _ expected: IntegrationError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as IntegrationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }
}

struct RegistryStore {
    let registry: IntegrationClientRegistry
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
