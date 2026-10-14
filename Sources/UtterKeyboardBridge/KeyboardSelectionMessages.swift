import Foundation

public struct KeyboardSelectionReview: Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let lease: KeyboardLease
    public let target: KeyboardSelectionTarget
    public let recognizedInstruction: String
    public let candidate: String
    public let expiresAt: Date

    public init(id: UUID, sessionID: UUID, lease: KeyboardLease, target: KeyboardSelectionTarget,
                recognizedInstruction: String, candidate: String, expiresAt: Date) {
        self.id = id; self.sessionID = sessionID; self.lease = lease; self.target = target
        self.recognizedInstruction = recognizedInstruction; self.candidate = candidate; self.expiresAt = expiresAt
    }

    public func isApplicable(at now: Date) -> Bool {
        target.isValid(at: now) && lease.documentID == target.documentID && expiresAt > now &&
        expiresAt <= target.expiresAt && !recognizedInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        recognizedInstruction.utf8.count <= 8192 && !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && candidate.utf8.count <= 8192
    }
}

public struct KeyboardSelectionRestoration: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let sessionID: UUID
    public let lease: KeyboardLease
    public let expiresAt: Date

    public init(operationID: UUID, sessionID: UUID, lease: KeyboardLease, expiresAt: Date) {
        self.operationID = operationID; self.sessionID = sessionID; self.lease = lease; self.expiresAt = expiresAt
    }

    public func isValid(at now: Date) -> Bool { expiresAt > now && expiresAt.timeIntervalSince(now) <= KeyboardSelectionTarget.lifetime }
}

public enum KeyboardSelectionOperationKind: String, Codable, Sendable { case apply, restore }

public struct KeyboardSelectionOperation: Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let lease: KeyboardLease
    public let kind: KeyboardSelectionOperationKind
    public let proposalID: UUID?
    public let restorationID: UUID?
    public let expiresAt: Date

    public init(id: UUID = UUID(), sessionID: UUID, lease: KeyboardLease, kind: KeyboardSelectionOperationKind,
                proposalID: UUID? = nil, restorationID: UUID? = nil, expiresAt: Date = Date().addingTimeInterval(10)) {
        self.id = id; self.sessionID = sessionID; self.lease = lease; self.kind = kind
        self.proposalID = proposalID; self.restorationID = restorationID; self.expiresAt = expiresAt
    }

    public func isValid(at now: Date) -> Bool {
        expiresAt > now && expiresAt.timeIntervalSince(now) <= 10 &&
        (kind == .apply ? proposalID != nil && restorationID == nil : restorationID != nil && proposalID == nil)
    }
}

public struct KeyboardSelectionAcknowledgement: Codable, Equatable, Sendable {
    public let operation: KeyboardSelectionOperation
    public let wrote: Bool
    public let confirmed: Bool
    public let createdAt: Date

    public init(operation: KeyboardSelectionOperation, wrote: Bool, confirmed: Bool, createdAt: Date = Date()) {
        self.operation = operation; self.wrote = wrote; self.confirmed = confirmed; self.createdAt = createdAt
    }

    public func isValid(for expected: KeyboardSelectionOperation, at now: Date) -> Bool {
        operation == expected && expected.isValid(at: now) && createdAt <= now && createdAt <= expected.expiresAt && (!confirmed || wrote)
    }
}
