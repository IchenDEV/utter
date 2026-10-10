import UtterContracts
import Foundation
import XCTest
@testable import UtterData

final class IntegrationAuthTests: XCTestCase {
    func testRegistryStartsEmpty() {
        let store = registry()
        defer { store.cleanup() }

        XCTAssertTrue(store.registry.approvedClients().isEmpty)
        XCTAssertNil(store.registry.client(id: "missing"))
        XCTAssertFalse(store.registry.isAuthorized(clientID: "missing", capability: .record))
    }

    func testApprovingClientPersistsIdentity() throws {
        let store = registry()
        defer { store.cleanup() }
        let client = makeClient(
            id: "cli:test",
            displayName: "Test CLI",
            transport: .cli,
            capabilities: [.record]
        )

        store.registry.approve(client)

        let persisted = try XCTUnwrap(store.registry.client(id: "cli:test"))
        XCTAssertEqual(persisted, client)
        XCTAssertEqual(store.registry.approvedClients(), [client])
    }

    func testApprovedClientPersistsAcrossRegistryInstances() throws {
        let store = registry()
        defer { store.cleanup() }
        let client = makeClient(
            id: "cli:shared",
            displayName: "Shared CLI",
            transport: .cli,
            capabilities: [.record]
        )

        store.registry.approve(client)
        let secondRegistry = IntegrationClientRegistry(defaults: store.defaults, reportError: { _ in })

        let persisted = try XCTUnwrap(secondRegistry.client(id: client.id))
        XCTAssertEqual(persisted, client)
    }

    func testAuthorizationRequiresApprovedClientAndCapability() {
        let store = registry()
        defer { store.cleanup() }
        let client = makeClient(
            id: "http:test",
            displayName: "Local HTTP",
            transport: .http,
            capabilities: [.record]
        )

        store.registry.approve(client)

        XCTAssertTrue(store.registry.isAuthorized(clientID: client.id, capability: .record))
        XCTAssertFalse(store.registry.isAuthorized(clientID: client.id, capability: .streamEvents))
        XCTAssertFalse(store.registry.isAuthorized(clientID: "http:other", capability: .record))
    }

    func testRevokingClientRemovesAccess() {
        let store = registry()
        defer { store.cleanup() }
        let client = makeClient(
            id: "xpc:test",
            displayName: "Helper",
            transport: .xpc,
            capabilities: [.record, .manageClients]
        )
        store.registry.approve(client)

        store.registry.revoke(clientID: client.id)

        XCTAssertNil(store.registry.client(id: client.id))
        XCTAssertTrue(store.registry.approvedClients().isEmpty)
        XCTAssertFalse(store.registry.isAuthorized(clientID: client.id, capability: .record))
    }

    func testMarkUsedUpdatesLastUsedAt() throws {
        let store = registry()
        defer { store.cleanup() }
        let usedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let client = makeClient(
            id: "cli:used",
            displayName: "Used CLI",
            transport: .cli,
            capabilities: [.record]
        )
        store.registry.approve(client)

        store.registry.markUsed(clientID: client.id, at: usedAt)

        let persisted = try XCTUnwrap(store.registry.client(id: client.id))
        XCTAssertEqual(persisted.firstApprovedAt, client.firstApprovedAt)
        XCTAssertEqual(persisted.lastUsedAt, usedAt)
    }

    func testReapprovingClientPreservesAuditFieldsWhileUpdatingMetadata() throws {
        let store = registry()
        defer { store.cleanup() }
        let firstApprovedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastUsedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let client = makeClient(
            id: "http:stable",
            displayName: "Old Name",
            transport: .http,
            capabilities: [.record],
            firstApprovedAt: firstApprovedAt
        )
        let replacement = IntegrationClient(
            id: client.id,
            displayName: "New Name",
            bundleIdentifier: "com.example.new",
            teamIdentifier: "TEAMNEW",
            codeRequirement: "anchor apple",
            transport: .xpc,
            capabilities: [.streamEvents, .manageClients],
            firstApprovedAt: Date(timeIntervalSince1970: 1_900_000_000),
            lastUsedAt: nil
        )
        store.registry.approve(client)
        store.registry.markUsed(clientID: client.id, at: lastUsedAt)

        store.registry.approve(replacement)

        let persisted = try XCTUnwrap(store.registry.client(id: client.id))
        XCTAssertEqual(persisted.displayName, "New Name")
        XCTAssertEqual(persisted.bundleIdentifier, "com.example.new")
        XCTAssertEqual(persisted.teamIdentifier, "TEAMNEW")
        XCTAssertEqual(persisted.codeRequirement, "anchor apple")
        XCTAssertEqual(persisted.transport, .xpc)
        XCTAssertEqual(persisted.capabilities, [.streamEvents, .manageClients])
        XCTAssertEqual(persisted.firstApprovedAt, firstApprovedAt)
        XCTAssertEqual(persisted.lastUsedAt, lastUsedAt)
    }

    func testCorruptStoredDataFailsClosedAndIsNotOverwritten() {
        let store = registry()
        defer { store.cleanup() }
        let corruptData = Data("not-json".utf8)
        store.defaults.set(corruptData, forKey: store.key)

        XCTAssertTrue(store.registry.approvedClients().isEmpty)
        XCTAssertNil(store.registry.client(id: "cli:corrupt"))
        XCTAssertFalse(store.registry.isAuthorized(clientID: "cli:corrupt", capability: .record))

        store.registry.approve(makeClient(
            id: "cli:corrupt",
            displayName: "Corrupt CLI",
            transport: .cli,
            capabilities: [.record]
        ))
        XCTAssertEqual(store.defaults.data(forKey: store.key), corruptData)

        store.registry.revoke(clientID: "cli:corrupt")
        XCTAssertEqual(store.defaults.data(forKey: store.key), corruptData)

        store.registry.markUsed(clientID: "cli:corrupt")
        XCTAssertEqual(store.defaults.data(forKey: store.key), corruptData)
    }

    private func registry() -> RegistryStore {
        let suiteName = "IntegrationAuthTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RegistryStore(
            registry: IntegrationClientRegistry(defaults: defaults, reportError: { _ in }),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func makeClient(
        id: String,
        displayName: String,
        transport: IntegrationClient.Transport,
        capabilities: Set<IntegrationClient.Capability>,
        firstApprovedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> IntegrationClient {
        IntegrationClient(
            id: id,
            displayName: displayName,
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: nil,
            transport: transport,
            capabilities: capabilities,
            firstApprovedAt: firstApprovedAt,
            lastUsedAt: nil
        )
    }
}

private struct RegistryStore {
    let registry: IntegrationClientRegistry
    let defaults: UserDefaults
    let suiteName: String
    let key = "integrationApprovedClients"

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
