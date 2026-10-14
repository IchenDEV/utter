import Foundation

/// The public keyboard proxy exposes a bounded selection, never a global document range.
public struct KeyboardSelectionTarget: Codable, Equatable, Sendable {
    public static let lifetime: TimeInterval = 120
    public static let contextLimit = 256
    public let documentID: UUID
    public let original: String
    public let before: String
    public let after: String
    public let createdAt: Date
    public var expiresAt: Date { createdAt.addingTimeInterval(Self.lifetime) }

    public init(documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date = Date()) throws {
        guard let documentID, let selectedText, !selectedText.isEmpty,
              let contextBefore, let contextAfter else { throw BridgeError.invalidTarget }
        self.documentID = documentID; original = selectedText
        before = String(contextBefore.suffix(Self.contextLimit)); after = String(contextAfter.prefix(Self.contextLimit))
        createdAt = now
        guard isValid(at: now) else { throw BridgeError.tooLarge }
    }

    public func isValid(at now: Date) -> Bool {
        createdAt <= now && expiresAt > now && !original.isEmpty && original.utf8.count <= 8192 &&
        before.count <= Self.contextLimit && after.count <= Self.contextLimit &&
        before.utf8.count <= 4096 && after.utf8.count <= 4096
    }

    public func matches(documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date = Date()) -> Bool {
        guard isValid(at: now), documentID == self.documentID, let selectedText,
              selectedText.utf8.elementsEqual(original.utf8), let contextBefore, let contextAfter else { return false }
        return String(contextBefore.suffix(Self.contextLimit)).utf8.elementsEqual(before.utf8) &&
            String(contextAfter.prefix(Self.contextLimit)).utf8.elementsEqual(after.utf8)
    }

    func containsReplacement(_ text: String, documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date) -> Bool {
        guard isValid(at: now), documentID == self.documentID, selectedText?.isEmpty != false,
              let contextBefore, let contextAfter else { return false }
        // Truncated or empty readback cannot prove that the complete replacement is ours.
        let expected = before + text
        return contextBefore.utf8.suffix(expected.utf8.count).elementsEqual(expected.utf8) &&
            String(contextAfter.prefix(Self.contextLimit)).utf8.elementsEqual(after.utf8)
    }

    func hasIndependentSpan(_ text: String) -> Bool {
        Array(before + text + after) == Array(before) + Array(text) + Array(after)
    }
}

/// Consumes write authority before the native proxy can have an effect. Uncertain writes cannot retry.
public struct KeyboardSelectionEdit: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case review, applying, applied, restoring, restored, cancelled, uncertain }
    public let id: UUID
    public let target: KeyboardSelectionTarget
    public let candidate: String
    public private(set) var phase = Phase.review

    public init(id: UUID, target: KeyboardSelectionTarget, candidate: String, now: Date = Date()) throws {
        guard target.isValid(at: now) else { throw BridgeError.expired }
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !candidate.utf8.elementsEqual(target.original.utf8) else { throw BridgeError.invalidMessage }
        guard candidate.utf8.count <= 8192 else { throw BridgeError.tooLarge }
        guard target.hasIndependentSpan(target.original), target.hasIndependentSpan(candidate) else { throw BridgeError.invalidTarget }
        self.id = id; self.target = target; self.candidate = candidate
    }

    public mutating func beginApply(documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date = Date()) throws -> String {
        guard phase == .review else { throw BridgeError.alreadyConsumed }
        guard target.matches(documentID: documentID, selectedText: selectedText, contextBefore: contextBefore, contextAfter: contextAfter, now: now) else {
            phase = .cancelled; throw BridgeError.invalidTarget
        }
        phase = .applying
        return candidate
    }

    @discardableResult
    public mutating func confirmApply(documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date = Date()) -> Bool {
        guard phase == .applying else { return false }
        let confirmed = target.containsReplacement(candidate, documentID: documentID, selectedText: selectedText,
                                                   contextBefore: contextBefore, contextAfter: contextAfter, now: now)
        phase = confirmed ? .applied : .uncertain
        return confirmed
    }

    public mutating func beginRestore(documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date = Date()) throws -> StreamingEdit {
        guard phase == .applied else { throw BridgeError.alreadyConsumed }
        guard target.containsReplacement(candidate, documentID: documentID, selectedText: selectedText,
                                          contextBefore: contextBefore, contextAfter: contextAfter, now: now) else {
            phase = .cancelled; throw BridgeError.invalidTarget
        }
        phase = .restoring
        let common = zip(candidate, target.original).prefix { String($0).utf8.elementsEqual(String($1).utf8) }.count
        return StreamingEdit(deleteCount: candidate.count - common, insert: String(target.original.dropFirst(common)))
    }

    @discardableResult
    public mutating func confirmRestore(documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date = Date()) -> Bool {
        guard phase == .restoring else { return false }
        let confirmed = target.containsReplacement(target.original, documentID: documentID, selectedText: selectedText,
                                                   contextBefore: contextBefore, contextAfter: contextAfter, now: now)
        phase = confirmed ? .restored : .uncertain
        return confirmed
    }

    public func hasConfirmedValue(documentID: UUID?, selectedText: String?, contextBefore: String?, contextAfter: String?, now: Date = Date()) -> Bool {
        let text: String
        switch phase {
        case .applied: text = candidate
        case .restored: text = target.original
        default: return false
        }
        return target.containsReplacement(text, documentID: documentID, selectedText: selectedText,
                                          contextBefore: contextBefore, contextAfter: contextAfter, now: now)
    }

    public mutating func invalidate() { phase = .cancelled }
}
