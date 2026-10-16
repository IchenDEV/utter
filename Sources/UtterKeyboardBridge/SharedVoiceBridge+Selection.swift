import Foundation

extension SharedVoiceBridge {
    // The text limits apply before encoding; this also bounds worst-case escaped JSON.
    static let selectionPayloadLimit = 256 * 1024

    public func publishSelectionReview(_ review: KeyboardSelectionReview) throws {
        guard review.isApplicable(at: Date()), try selectionSession(review.sessionID, lease: review.lease) else { throw BridgeError.invalidTarget }
        try write(review, name: "selection-review.json", limit: Self.selectionPayloadLimit)
    }

    public func selectionReview(sessionID: UUID) throws -> KeyboardSelectionReview? {
        try pruneSelectionReview()
        guard let review: KeyboardSelectionReview = try read("selection-review.json", limit: Self.selectionPayloadLimit),
              review.sessionID == sessionID, review.isApplicable(at: Date()),
              try selectionSession(sessionID, lease: review.lease) else { return nil }
        return review
    }

    func pruneSelectionReview(status: VoiceStatus? = nil) throws {
        try coordinated("selection-review.json", writing: true) { url in
            guard let review: KeyboardSelectionReview = try self.decode(url, limit: Self.selectionPayloadLimit) else { return }
            let invalidSession = status.map { !$0.isBusy || $0.selectionMode != true || $0.requestID != review.sessionID || $0.generation != review.lease.generation } ?? false
            if !review.isApplicable(at: Date()) || invalidSession { try self.files.removeItem(at: url) }
        }
    }

    public func clearSelectionReview(sessionID: UUID) throws {
        try coordinated("selection-review.json", writing: true) { url in
            guard let review: KeyboardSelectionReview = try self.decode(url, limit: Self.selectionPayloadLimit), review.sessionID == sessionID else { return }
            try self.files.removeItem(at: url)
        }
    }

    public func publishSelectionOperation(_ operation: KeyboardSelectionOperation) throws {
        guard operation.isValid(at: Date()), try selectionSession(operation.sessionID, lease: operation.lease) else { throw BridgeError.invalidTarget }
        try coordinated("selection-output-\(operation.sessionID).json", writing: true) { url in
            guard !self.files.fileExists(atPath: url.path),
                  !self.files.fileExists(atPath: self.root.appendingPathComponent("selection-taken-\(operation.id).json").path) else { throw BridgeError.alreadyConsumed }
            try self.writeData(self.encoder.encode(operation), to: url)
        }
    }

    public func selectionOperation(sessionID: UUID) throws -> KeyboardSelectionOperation? {
        guard let operation: KeyboardSelectionOperation = try read("selection-output-\(sessionID).json", limit: 4096),
              operation.sessionID == sessionID, operation.isValid(at: Date()),
              try selectionSession(sessionID, lease: operation.lease) else { return nil }
        return operation
    }

    public func takeSelectionOperation(_ expected: KeyboardSelectionOperation) throws {
        try coordinated("selection-output-\(expected.sessionID).json", writing: true) { url in
            let marker = self.root.appendingPathComponent("selection-taken-\(expected.id).json")
            guard !self.files.fileExists(atPath: marker.path) else { throw BridgeError.alreadyConsumed }
            guard let operation: KeyboardSelectionOperation = try self.decode(url, limit: 4096), operation == expected,
                  operation.isValid(at: Date()), try self.selectionSession(operation.sessionID, lease: operation.lease) else { throw BridgeError.invalidTarget }
            try self.writeData(self.encoder.encode(operation), to: marker)
            try self.files.removeItem(at: url)
        }
    }

    public func acknowledgeSelection(_ acknowledgement: KeyboardSelectionAcknowledgement,
                                     restoration: KeyboardSelectionRestoration? = nil) throws {
        let operation = acknowledgement.operation
        try coordinated("selection-taken-\(operation.id).json", writing: true) { marker in
            guard let taken: KeyboardSelectionOperation = try self.decode(marker, limit: 4096), taken == operation,
                  acknowledgement.isValid(for: taken, at: Date()),
                  try self.selectionSession(operation.sessionID, lease: operation.lease) else { throw BridgeError.invalidTarget }
            let url = self.root.appendingPathComponent("selection-ack-\(operation.id).json")
            guard !self.files.fileExists(atPath: url.path) else { throw BridgeError.alreadyConsumed }
            if let restoration {
                guard restoration.isValid(at: Date()), acknowledgement.confirmed, acknowledgement.wrote,
                      operation.kind == .apply, restoration.operationID == operation.id,
                      restoration.sessionID == operation.sessionID, restoration.lease == operation.lease else { throw BridgeError.invalidTarget }
                // Metadata precedes the acknowledgement that lets the app settle and close this operation.
                try self.write(restoration, name: "selection-restoration.json", limit: 4096)
            }
            try self.writeData(self.encoder.encode(acknowledgement), to: url)
        }
    }

    public func selectionAcknowledgement(for operation: KeyboardSelectionOperation) throws -> KeyboardSelectionAcknowledgement? {
        guard let acknowledgement: KeyboardSelectionAcknowledgement = try read("selection-ack-\(operation.id).json", limit: 4096),
              acknowledgement.isValid(for: operation, at: Date()),
              try selectionSession(operation.sessionID, lease: operation.lease) else { return nil }
        return acknowledgement
    }

    public func clearSelectionOperation(_ operation: KeyboardSelectionOperation) throws {
        try coordinated("selection-output-\(operation.sessionID).json", writing: true) { url in
            guard let current: KeyboardSelectionOperation = try self.decode(url, limit: 4096), current == operation else { return }
            try self.files.removeItem(at: url)
        }
        try remove("selection-taken-\(operation.id).json")
        try remove("selection-ack-\(operation.id).json")
    }

    public func selectionRestoration() throws -> KeyboardSelectionRestoration? {
        guard let value: KeyboardSelectionRestoration = try read("selection-restoration.json", limit: 4096), value.isValid(at: Date()) else { return nil }
        return value
    }

    public func clearSelectionRestoration(operationID: UUID) throws {
        try coordinated("selection-restoration.json", writing: true) { url in
            guard let value: KeyboardSelectionRestoration = try self.decode(url, limit: 4096), value.operationID == operationID else { return }
            try self.files.removeItem(at: url)
        }
    }

    func selectionSession(_ sessionID: UUID, lease: KeyboardLease) throws -> Bool {
        guard let status = try status(), status.selectionMode == true, status.isBusy, status.requestID == sessionID,
              status.generation == lease.generation, status.leaseID == lease.id, status.documentID == lease.documentID,
              let current = try self.lease(lease.id) else { return false }
        return current.documentID == lease.documentID && current.generation == lease.generation
    }
}
