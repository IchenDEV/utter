import Foundation

public enum VoiceAction: String, Codable, Sendable { case start, stop, cancel, attach, startSelection, applySelection, restoreSelection }
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
    public let captureRequestID: UUID?
    public let selectionTarget: KeyboardSelectionTarget?
    public let proposalID: UUID?
    public let restoreOperationID: UUID?

    public init(id: UUID = UUID(), lease: KeyboardLease, action: VoiceAction, captureRequestID: UUID? = nil,
                selectionTarget: KeyboardSelectionTarget? = nil, proposalID: UUID? = nil, restoreOperationID: UUID? = nil) {
        version = [.startSelection, .applySelection, .restoreSelection].contains(action) ? 2 : 1
        self.id = id; self.lease = lease; self.action = action
        self.captureRequestID = captureRequestID
        self.selectionTarget = selectionTarget; self.proposalID = proposalID; self.restoreOperationID = restoreOperationID
        expiresAt = Date().addingTimeInterval(10)
    }

    public func isValid(at now: Date) -> Bool {
        guard expiresAt > now, expiresAt.timeIntervalSince(now) <= 10 else { return false }
        switch action {
        case .startSelection:
            return version == 2 && captureRequestID == nil && proposalID == nil && restoreOperationID == nil &&
                selectionTarget?.isValid(at: now) == true && selectionTarget?.documentID == lease.documentID
        case .applySelection:
            return version == 2 && proposalID != nil && selectionTarget == nil && captureRequestID == nil && restoreOperationID == nil
        case .restoreSelection:
            return version == 2 && restoreOperationID != nil && selectionTarget == nil && proposalID == nil && captureRequestID == nil
        case .start, .stop, .cancel, .attach:
            return version == 1 && selectionTarget == nil && proposalID == nil && restoreOperationID == nil
        }
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
    /// The bounded Debug trial accepts one target only after real capture starts in the app.
    public var captureFromApp: Bool?
    public var selectionMode: Bool?

    public init(generation: UUID = UUID(), phase: VoicePhase = .disabled) {
        self.generation = generation; self.phase = phase
    }
    public var isBusy: Bool { [.preparing, .recording, .processing].contains(phase) }
    public static let heartbeatTimeout: TimeInterval = 20
    public var isStandbyLive: Bool {
        phase != .disabled && heartbeat.map { Date().timeIntervalSince($0) < Self.heartbeatTimeout } == true
    }
    public var canAttachKeyboardTarget: Bool {
        captureFromApp == true && phase == .recording && requestID != nil && leaseID == nil && documentID == nil && isStandbyLive
    }
}

public enum BridgeError: Error, Equatable { case unavailable, invalidMessage, expired, alreadyConsumed, invalidTarget, tooLarge, io }
