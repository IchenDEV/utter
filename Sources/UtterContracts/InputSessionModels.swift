import Foundation

package struct InputSessionRequest: Codable, Equatable, Sendable {
    package var mode: OutputMode?
    package var language: InputLanguage?
    package var useScreenContext: Bool?

    package enum CodingKeys: String, CodingKey {
        case mode
        case language
        case useScreenContext = "use_screen_context"
    }

    package init(mode: OutputMode? = nil, language: InputLanguage? = nil, useScreenContext: Bool? = nil) {
        self.mode = mode
        self.language = language
        self.useScreenContext = useScreenContext
    }
}

package struct InputSession: Codable, Equatable, Identifiable {
    package let id: UUID
    package var request: InputSessionRequest
    package var state: InputSessionState
    package var createdAt: Date
    package var updatedAt: Date

    package enum CodingKeys: String, CodingKey {
        case id
        case request
        case state
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    package init(id: UUID, request: InputSessionRequest, state: InputSessionState, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.request = request
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

package enum InputSessionState: String, Codable, Equatable {
    case created
    case recording
    case processing
    case completed
    case cancelled
    case failed

    package var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        case .created, .recording, .processing:
            return false
        }
    }
}

package struct InputSessionEvent: Codable, Equatable {
    package enum EventType: String, Codable {
        case sessionCreated = "session.created"
        case recordingStarted = "recording.started"
        case audioReceived = "audio.received"
        case transcriptPartial = "transcript.partial"
        case transcriptFinal = "transcript.final"
        case processingStarted = "processing.started"
        case textFinal = "text.final"
        case sessionCompleted = "session.completed"
        case sessionCancelled = "session.cancelled"
        case sessionFailed = "session.failed"
    }

    package let type: EventType
    package let sessionID: UUID
    package let sequence: Int
    package let timestamp: Date
    package let text: String?
    package let error: IntegrationError.Payload?

    package enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "session_id"
        case sequence
        case timestamp
        case text
        case error
    }

    package init(type: EventType, sessionID: UUID, sequence: Int, timestamp: Date, text: String? = nil, error: IntegrationError.Payload? = nil) {
        self.type = type
        self.sessionID = sessionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.text = text
        self.error = error
    }
}

package struct InputSessionResult: Codable, Equatable {
    package let session: InputSession
    package let transcript: String
    package let text: String

    package init(session: InputSession, transcript: String, text: String) {
        self.session = session
        self.transcript = transcript
        self.text = text
    }
}

extension InputSessionEvent.EventType {
    package var closesEventStream: Bool {
        switch self {
        case .sessionCompleted, .sessionCancelled, .sessionFailed:
            return true
        case .sessionCreated, .recordingStarted, .audioReceived, .transcriptPartial,
             .transcriptFinal, .processingStarted, .textFinal:
            return false
        }
    }
}

extension JSONEncoder {
    package static var integration: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    package static var integration: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
