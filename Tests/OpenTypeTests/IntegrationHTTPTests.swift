import Foundation
import XCTest
@testable import OpenType

final class IntegrationHTTPTests: XCTestCase {
    func testRequestParsesMethodPathHeaderAndBody() throws {
        let requestData = Data(
            "POST /v1/sessions HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n\r\n{\"mode\":\"direct\"}".utf8
        )

        let request = try XCTUnwrap(IntegrationHTTPRequest.parse(from: requestData))

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/sessions")
        XCTAssertEqual(request.header("host"), "localhost")
        XCTAssertEqual(request.header("CONTENT-TYPE"), "application/json")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), "{\"mode\":\"direct\"}")
    }

    func testBearerTokenExtractionUsesCaseInsensitiveHeaderNameAndBearerScheme() throws {
        let requestData = Data(
            "GET /v1/sessions/00000000-0000-0000-0000-000000000001/events HTTP/1.1\r\nauthorization: Bearer test-token\r\n\r\n".utf8
        )

        let request = try XCTUnwrap(IntegrationHTTPRequest.parse(from: requestData))

        XCTAssertEqual(request.header("Authorization"), "Bearer test-token")
        XCTAssertEqual(request.bearerToken, "test-token")
    }

    func testRoutesMatchKnownIntegrationEndpoints() throws {
        let sessionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

        XCTAssertEqual(IntegrationHTTPRoute.match(method: "POST", path: "/v1/sessions"), .createSession)
        XCTAssertEqual(
            IntegrationHTTPRoute.match(method: "GET", path: "/v1/sessions/\(sessionID.uuidString)/events"),
            .events(sessionID)
        )
        XCTAssertEqual(
            IntegrationHTTPRoute.match(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/recording/start"),
            .startRecording(sessionID)
        )
        XCTAssertEqual(
            IntegrationHTTPRoute.match(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/audio"),
            .submitAudio(sessionID)
        )
        XCTAssertEqual(
            IntegrationHTTPRoute.match(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/recording/stop"),
            .stopRecording(sessionID)
        )
        XCTAssertEqual(
            IntegrationHTTPRoute.match(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/cancel"),
            .cancel(sessionID)
        )
    }

    func testRoutesReturnNotFoundForInvalidUUIDAndMethodMismatch() {
        XCTAssertEqual(
            IntegrationHTTPRoute.match(method: "GET", path: "/v1/sessions"),
            .notFound
        )
        XCTAssertEqual(
            IntegrationHTTPRoute.match(method: "GET", path: "/v1/sessions/not-a-uuid/events"),
            .notFound
        )
    }

    func testJSONResponseSerializesStatusHeadersAndBody() throws {
        let response = IntegrationHTTPResponse.json(["ok": true], statusCode: 201)
        let serialized = response.serialize()
        let serializedString = try XCTUnwrap(String(data: serialized, encoding: .utf8))

        XCTAssertTrue(serializedString.hasPrefix("HTTP/1.1 201 Created\r\n"))
        XCTAssertTrue(serializedString.contains("Content-Type: application/json\r\n"))
        XCTAssertTrue(serializedString.contains("Content-Length: 11\r\n"))
        XCTAssertTrue(serializedString.hasSuffix("\r\n\r\n{\"ok\":true}"))
    }

    func testSSEEncodingIncludesEventNameAndJSONData() throws {
        let sessionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let event = InputSessionEvent(
            type: .transcriptPartial,
            sessionID: sessionID,
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            text: "hello",
            error: nil
        )

        let data = try IntegrationSSE.encode([event])
        let string = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(string.contains("event: transcript.partial\n"))
        XCTAssertTrue(string.contains("data: {"))
        XCTAssertTrue(string.contains("\"type\":\"transcript.partial\""))
        XCTAssertTrue(string.hasSuffix("\n\n"))
    }

    func testHTTPServerStatusMapping() {
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.developerInterfaceDisabled), 401)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.unauthorizedClient), 401)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.busy), 409)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.sessionNotFound), 404)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.invalidSessionState), 409)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.permissionDenied), 400)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.modelNotReady), 400)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.noSpeechDetected), 400)
        XCTAssertEqual(IntegrationHTTPDispatcher.statusCode(for: IntegrationError.operationFailed), 500)
    }

    @MainActor
    func testHTTPServerDispatchRejectsUnauthorizedBearerToken() async throws {
        let store = registry()
        defer { store.cleanup() }
        let server = makeServer(
            registry: store.registry,
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "expected")
        )
        let request = try XCTUnwrap(IntegrationHTTPRequest.parse(from: Data(
            "POST /v1/sessions HTTP/1.1\r\nAuthorization: Bearer wrong\r\n\r\n".utf8
        )))

        let response = await server.dispatch(request)
        let payload = try JSONDecoder.integration.decode(IntegrationError.Payload.self, from: response.body)

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(payload, IntegrationError.unauthorizedClient.payload)
        XCTAssertNil(store.registry.client(id: IntegrationClient.localHTTP(tokenID: "wrong").id))
    }

    @MainActor
    func testHTTPServerDispatchApprovesTokenAndCreatesSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        let server = makeServer(
            registry: store.registry,
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token")
        )
        let request = try XCTUnwrap(IntegrationHTTPRequest.parse(from: Data(
            "POST /v1/sessions HTTP/1.1\r\nAuthorization: Bearer token\r\n\r\n".utf8
        )))

        let response = await server.dispatch(request)
        let session = try JSONDecoder.integration.decode(InputSession.self, from: response.body)

        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(session.state, .created)
        XCTAssertNotNil(store.registry.client(id: IntegrationClient.localHTTP(tokenID: "token").id))
    }

    @MainActor
    func testHTTPServerDispatchRequiresRegisteredCLIClient() async throws {
        let store = registry()
        defer { store.cleanup() }
        let client = IntegrationClient.localCLI(executablePath: "/Applications/Utter.app/Contents/MacOS/opentype-cli")
        let server = makeServer(
            registry: store.registry,
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token")
        )

        var request = try XCTUnwrap(IntegrationHTTPRequest.parse(from: Data(
            "POST /v1/sessions HTTP/1.1\r\nAuthorization: Bearer token\r\nX-OpenType-Client-ID: \(client.id)\r\n\r\n".utf8
        )))
        let unauthorizedResponse = await server.dispatch(request)
        XCTAssertEqual(unauthorizedResponse.statusCode, 401)

        store.registry.approve(client)
        request = try XCTUnwrap(IntegrationHTTPRequest.parse(from: Data(
            "POST /v1/sessions HTTP/1.1\r\nAuthorization: Bearer token\r\nX-OpenType-Client-ID: \(client.id)\r\n\r\n".utf8
        )))
        let response = await server.dispatch(request)
        let session = try JSONDecoder.integration.decode(InputSession.self, from: response.body)

        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(session.state, .created)
        XCTAssertNil(store.registry.client(id: IntegrationClient.localHTTP(tokenID: "token").id))
    }

    @MainActor
    private func makeServer(
        registry: IntegrationClientRegistry,
        settings: IntegrationServiceSettings
    ) -> IntegrationHTTPServer {
        let service = OpenTypeService(settings: settings, registry: registry)
        let coordinator = InputSessionCoordinator(service: service)
        return IntegrationHTTPServer(
            port: 49_999,
            service: service,
            coordinator: coordinator,
            registry: registry,
            settingsProvider: { settings }
        )
    }

    private func registry() -> RegistryStore {
        let suiteName = "IntegrationHTTPTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RegistryStore(
            registry: IntegrationClientRegistry(defaults: defaults),
            defaults: defaults,
            suiteName: suiteName
        )
    }
}

private struct RegistryStore {
    let registry: IntegrationClientRegistry
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
