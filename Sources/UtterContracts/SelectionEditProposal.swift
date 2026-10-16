import Foundation

package struct SelectionEditProposal: Equatable, Sendable {
    package let id: UUID
    package let sessionID: UUID
    package let targetID: UUID
    package let processIdentifier: Int32?
    package let originalSelection: String
    package let recognizedInstruction: String
    package let candidate: String
    package let expiresAt: Date
    package init(id: UUID = UUID(), sessionID: UUID, targetID: UUID, processIdentifier: Int32? = nil,
                 originalSelection: String, recognizedInstruction: String, candidate: String,
                 expiresAt: Date = Date().addingTimeInterval(120)) {
        self.id = id; self.sessionID = sessionID; self.targetID = targetID
        self.processIdentifier = processIdentifier; self.originalSelection = originalSelection
        self.recognizedInstruction = recognizedInstruction; self.candidate = candidate; self.expiresAt = expiresAt
    }
    package var isApplicable: Bool {
        Date() < expiresAt && !originalSelection.isEmpty
            && !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
