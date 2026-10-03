import UtterContracts
import Foundation
import XCTest
@testable import UtterContracts

final class IntegrationModelTests: XCTestCase {
    func testInputSessionEventEncodesStableJSONKeys() throws {
        let event = InputSessionEvent(
            type: .transcriptPartial,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sequence: 2,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            text: "hello",
            error: nil
        )

        let data = try JSONEncoder.integration.encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "transcript.partial")
        XCTAssertEqual(object["session_id"] as? String, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(object["sequence"] as? Int, 2)
        XCTAssertEqual(object["text"] as? String, "hello")
        XCTAssertNotNil(object["timestamp"])
        XCTAssertNil(object["error"])
    }

    func testIntegrationErrorPayloadUsesStableIdentifier() throws {
        let payload = IntegrationError.developerInterfaceDisabled.payload

        XCTAssertEqual(payload.error, "developer_interface_disabled")
        XCTAssertEqual(payload.message, "Developer interface is disabled.")

        let data = try JSONEncoder.integration.encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["error"] as? String, "developer_interface_disabled")
        XCTAssertEqual(object["message"] as? String, "Developer interface is disabled.")
    }

    func testInputSessionRequestDefaultsToCurrentSettingsWhenModeIsMissing() {
        let request = InputSessionRequest(mode: nil, language: nil, useScreenContext: nil)

        XCTAssertNil(request.mode)
        XCTAssertNil(request.language)
        XCTAssertNil(request.useScreenContext)
    }

    func testInputSessionRequestEncodesStableJSONKeys() throws {
        let request = InputSessionRequest(mode: .processed, language: .english, useScreenContext: true)

        let data = try JSONEncoder.integration.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["mode"] as? String, "processed")
        XCTAssertEqual(object["language"] as? String, "English")
        XCTAssertEqual(object["use_screen_context"] as? Bool, true)
        XCTAssertFalse(object.keys.contains("useScreenContext"))
    }

    func testInputSessionEncodesStableJSONKeys() throws {
        let session = InputSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            request: InputSessionRequest(mode: .direct, language: .auto, useScreenContext: false),
            state: .processing,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )

        let data = try JSONEncoder.integration.encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try XCTUnwrap(object["request"] as? [String: Any])

        XCTAssertEqual(object["id"] as? String, "00000000-0000-0000-0000-000000000002")
        XCTAssertEqual(object["state"] as? String, "processing")
        XCTAssertNotNil(object["created_at"])
        XCTAssertNotNil(object["updated_at"])
        XCTAssertFalse(object.keys.contains("createdAt"))
        XCTAssertFalse(object.keys.contains("updatedAt"))
        XCTAssertEqual(request["use_screen_context"] as? Bool, false)
        XCTAssertFalse(request.keys.contains("useScreenContext"))
    }

    func testEventTypeRawValuesRemainStable() {
        XCTAssertEqual(InputSessionEvent.EventType.sessionCreated.rawValue, "session.created")
        XCTAssertEqual(InputSessionEvent.EventType.recordingStarted.rawValue, "recording.started")
        XCTAssertEqual(InputSessionEvent.EventType.audioReceived.rawValue, "audio.received")
        XCTAssertEqual(InputSessionEvent.EventType.transcriptPartial.rawValue, "transcript.partial")
        XCTAssertEqual(InputSessionEvent.EventType.transcriptFinal.rawValue, "transcript.final")
        XCTAssertEqual(InputSessionEvent.EventType.processingStarted.rawValue, "processing.started")
        XCTAssertEqual(InputSessionEvent.EventType.textFinal.rawValue, "text.final")
        XCTAssertEqual(InputSessionEvent.EventType.sessionCompleted.rawValue, "session.completed")
        XCTAssertEqual(InputSessionEvent.EventType.sessionCancelled.rawValue, "session.cancelled")
        XCTAssertEqual(InputSessionEvent.EventType.sessionFailed.rawValue, "session.failed")
    }
}
