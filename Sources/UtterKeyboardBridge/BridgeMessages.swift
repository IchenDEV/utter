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

public struct VoiceStatus: Codable, Equatable, Sendable {
    public var version = 1
    public var generation: UUID
    public var phase: VoicePhase
    public var requestID: UUID?
    public var leaseID: UUID?
    public var documentID: UUID?
    public var text = ""
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
