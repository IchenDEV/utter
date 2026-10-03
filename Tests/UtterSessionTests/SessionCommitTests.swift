import Foundation
import XCTest
import UtterContracts
import UtterData
@testable import UtterSession

@MainActor
final class SessionCommitTests: XCTestCase {
    private func withFixture(_ operation: (OpenTypeService, IntegrationClientRegistry, String) async throws -> Void) async throws {
        let suite = "SessionCommitTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = IntegrationClientRegistry(defaults: defaults, reportError: { _ in })
        let client = IntegrationClient.localHTTP(tokenID: "token")
        registry.approve(client)
        let service = OpenTypeService(settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token"), registry: registry)
        try await operation(service, registry, client.id)
    }

    func testHistoryCallbackSeesSettledStateAndCannotCommitAgain() async throws {
        try await withFixture { service, _, clientID in
            let session = try await service.createSession(InputSessionRequest(), clientID: clientID)
            var records = 0
            try service.commitSession(sessionID: session.id, clientID: clientID, finalText: "final", record: {
                records += 1
                XCTAssertEqual(try? service.session(session.id, clientID: clientID)?.state, .completed)
                let events = try? service.snapshotEvents(sessionID: session.id, clientID: clientID)
                XCTAssertEqual(events?.suffix(2).map(\.type), [.textFinal, .sessionCompleted])
                do {
                    try service.commitSession(sessionID: session.id, clientID: clientID, finalText: "duplicate", record: { records += 1 })
                    XCTFail("A reentrant history callback committed a second result")
                } catch {
                    XCTAssertEqual(error as? IntegrationError, .invalidSessionState)
                }
            })
            XCTAssertEqual(records, 1)
            XCTAssertEqual(try service.snapshotEvents(sessionID: session.id, clientID: clientID).map(\.sequence), [1, 2, 3])
        }
    }

    func testTerminalObserverSeesBothEventsBeforeItsFirstCallback() async throws {
        try await withFixture { service, _, clientID in
            let session = try await service.createSession(InputSessionRequest(), clientID: clientID)
            var types: [InputSessionEvent.EventType] = []
            _ = try service.subscribeEvents(sessionID: session.id, clientID: clientID) { event in
                types.append(event.type)
                XCTAssertEqual(try? service.snapshotEvents(sessionID: session.id, clientID: clientID).suffix(2).map(\.type), [.textFinal, .sessionCompleted])
            }
            try service.commitSession(sessionID: session.id, clientID: clientID, finalText: "final")
            XCTAssertEqual(types, [.textFinal, .sessionCompleted])
        }
    }

    func testSubscriptionDuringHistorySettlementDoesNotReplayItsSnapshot() async throws {
        try await withFixture { service, _, clientID in
            let session = try await service.createSession(InputSessionRequest(), clientID: clientID)
            var live: [InputSessionEvent] = []
            try service.commitSession(sessionID: session.id, clientID: clientID, finalText: "final", record: {
                let subscription = try? service.subscribeEvents(sessionID: session.id, clientID: clientID) { live.append($0) }
                XCTAssertEqual(subscription?.snapshot.suffix(2).map(\.type), [.textFinal, .sessionCompleted])
            })
            XCTAssertTrue(live.isEmpty)
        }
    }

    func testReentrantPublicationWaitsUntilTheCurrentCallbackReturns() async throws {
        try await withFixture { service, _, clientID in
            let session = try await service.createSession(InputSessionRequest(), clientID: clientID)
            var observed: [Int] = []
            _ = try service.subscribeEvents(sessionID: session.id, clientID: clientID) { event in
                if event.sequence == 2 {
                    try? service.emitTranscriptPartial(sessionID: session.id, clientID: clientID, text: "nested")
                }
                observed.append(event.sequence)
            }
            try service.emitTranscriptPartial(sessionID: session.id, clientID: clientID, text: "first")
            XCTAssertEqual(observed, [2, 3])
        }
    }

    func testRevocationDuringCallbackImmediatelyStopsTheSubscription() async throws {
        try await withFixture { service, registry, clientID in
            let session = try await service.createSession(InputSessionRequest(), clientID: clientID)
            var types: [InputSessionEvent.EventType] = []
            _ = try service.subscribeEvents(sessionID: session.id, clientID: clientID) { event in
                types.append(event.type)
                registry.revoke(clientID: clientID)
            }
            try service.commitSession(sessionID: session.id, clientID: clientID, finalText: "final")
            XCTAssertEqual(types, [.textFinal])
        }
    }
}
