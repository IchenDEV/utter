import Foundation
import XCTest
import UtterContracts
import UtterData

final class IntegrationAuthorizationObservationTests: XCTestCase {
    func testAuthorizationChangesNotifyAndRetiredRegistryCannotWritePreferences() throws {
        let suite = "AuthorizationObservations-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = IntegrationClientRegistry(defaults: defaults, reportError: { _ in })
        let client = IntegrationClient.localHTTP(tokenID: "fixture")
        var calls = 0
        let observation = registry.observeAuthorization { calls += 1 }
        registry.approve(client)
        XCTAssertEqual(calls, 1)
        registry.markUsed(clientID: client.id)
        XCTAssertEqual(calls, 1)
        registry.revoke(clientID: client.id)
        XCTAssertEqual(calls, 2)
        registry.removeAuthorizationObserver(observation)
        registry.approve(client)
        XCTAssertEqual(calls, 2)
        let stored = defaults.data(forKey: "integrationApprovedClients")
        registry.close()
        registry.revoke(clientID: client.id)
        XCTAssertEqual(defaults.data(forKey: "integrationApprovedClients"), stored)
        XCTAssertFalse(registry.isAuthorized(clientID: client.id, capability: .record))
    }

    func testRemovingAnotherObserverInsideDeliverySuppressesItsCallback() throws {
        let suite = "AuthorizationRemoval-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = IntegrationClientRegistry(defaults: defaults, reportError: { _ in })
        var first: UUID!
        var second: UUID!
        var calls = 0
        first = registry.observeAuthorization { calls += 1; registry.removeAuthorizationObserver(second) }
        second = registry.observeAuthorization { calls += 1; registry.removeAuthorizationObserver(first) }
        registry.approve(IntegrationClient.localHTTP(tokenID: "fixture"))
        XCTAssertEqual(calls, 1)
    }
}
