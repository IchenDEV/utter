import Foundation

public enum VoiceAction: String, Codable, Sendable { case start, stop, cancel }
public enum VoicePhase: String, Codable, Sendable { case disabled, ready, preparing, recording, processing, result, cancelled, failed }

public struct KeyboardLease: Codable, Equatable, Sendable {
    public let id: UUID
    public let generation: UUID
    public let documentID: UUID
    public var expiresAt: Date

    public init(id: UUID = UUID(), generation: UUID, documentID: UUID, expiresAt: Date = Date().addingTimeInterval(5)) {
        self.id = id; self.generation = generation; self.documentID = documentID; self.expiresAt = expiresAt
    }
}

public struct VoiceCommand: Codable, Sendable {
    public let version: Int
    public let id: UUID
    public let lease: KeyboardLease
    public let action: VoiceAction
    public let expiresAt: Date

    public init(id: UUID = UUID(), lease: KeyboardLease, action: VoiceAction) {
        version = 1; self.id = id; self.lease = lease; self.action = action
        expiresAt = Date().addingTimeInterval(10)
    }
}

/// State of the language-model rewrite that follows a finished dictation.
public enum PolishState: String, Codable, Sendable { case pending, done, failed }

/// Left by the keyboard just before it sends the user to the main app, so the keyboard that comes back can
/// start recording without a second tap. It expires quickly and is used once.
public struct DictationIntent: Codable, Equatable, Sendable {
    public static let lifetime: TimeInterval = 60
    public let id: UUID
    public let documentID: UUID
    public let createdAt: Date
    public var expiresAt: Date { createdAt.addingTimeInterval(Self.lifetime) }

    public init(id: UUID = UUID(), documentID: UUID, createdAt: Date = Date()) {
        self.id = id; self.documentID = documentID; self.createdAt = createdAt
    }
}

public struct VoiceStatus: Codable, Equatable, Sendable {
    public var version = 1
    public var generation: UUID
    public var phase: VoicePhase
    public var requestID: UUID?
    public var leaseID: UUID?
    public var documentID: UUID?
    /// While recording or processing this is the live draft; in `result` it is the final text.
    public var text = ""
    /// Rewrite of `text` by a language model. Optional so older status files still decode.
    public var polish: PolishState?
    public var polished: String?
    public var errorKey: String?
    public var updatedAt = Date()
    public var expiresAt: Date?
    /// Set only while the main app can still receive keyboard commands in the background.
    public var heartbeat: Date?

    public init(generation: UUID = UUID(), phase: VoicePhase = .disabled) {
        self.generation = generation; self.phase = phase
    }
    public var isBusy: Bool { [.preparing, .recording, .processing].contains(phase) }
    public static let heartbeatTimeout: TimeInterval = 20
    public var isStandbyLive: Bool {
        phase != .disabled && heartbeat.map { Date().timeIntervalSince($0) < Self.heartbeatTimeout } == true
    }
}

public enum BridgeError: Error, Equatable { case unavailable, invalidMessage, expired, alreadyConsumed, invalidTarget, tooLarge, io }
