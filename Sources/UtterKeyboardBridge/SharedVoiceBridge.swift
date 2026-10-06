import Foundation

@MainActor
public final class SharedVoiceBridge {
    let root: URL
    let files = FileManager.default
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    public init(container: URL) throws {
        root = container.appendingPathComponent("UtterVoice-v1", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        #if os(iOS)
        try files.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        #endif
    }

    public func status() throws -> VoiceStatus? {
        try coordinated("status.json", writing: true) { url in
            guard var value: VoiceStatus = try self.decode(url, limit: 32 * 1024) else { return nil }
            guard value.version == 1 else { throw BridgeError.invalidMessage }
            let consumed = value.requestID.map(self.isConsumed) ?? false
            if value.phase == .result && (consumed || (value.expiresAt ?? .distantPast) <= Date()) {
                value.text = ""; value.phase = .ready; value.expiresAt = nil
                try self.writeData(self.encoder.encode(value), to: url)
            }
            return value
        }
    }

    public func publish(_ status: VoiceStatus) throws {
        guard status.version == 1 else { throw BridgeError.invalidMessage }
        try write(status, name: "status.json", limit: 32 * 1024)
    }

    public func renew(_ lease: KeyboardLease) throws {
        guard lease.expiresAt > Date(), lease.expiresAt.timeIntervalSinceNow <= 6 else { throw BridgeError.expired }
        try write(lease, name: "lease-\(lease.id).json", limit: 4096)
    }

    public func lease(_ id: UUID) throws -> KeyboardLease? {
        let value: KeyboardLease? = try read("lease-\(id).json", limit: 4096)
        return value?.expiresAt ?? .distantPast > Date() ? value : nil
    }

    public func revoke(_ id: UUID) throws { try remove("lease-\(id).json") }

    public func post(_ command: VoiceCommand) throws {
        guard command.version == 1, command.expiresAt > Date() else { throw BridgeError.invalidMessage }
        try write(command, name: "command-\(command.id).json", limit: 4096)
    }

    public func command(_ id: UUID) throws -> VoiceCommand {
        guard let value: VoiceCommand = try read("command-\(id).json", limit: 4096), value.id == id else { throw BridgeError.invalidMessage }
        return value
    }

    public func take(_ id: UUID, generation: UUID) throws -> VoiceCommand {
        try coordinated("command-\(id).json", writing: true) { url in
            let accepted = self.root.appendingPathComponent("accepted-\(id).json")
            guard !self.files.fileExists(atPath: accepted.path) else { throw BridgeError.alreadyConsumed }
            guard let command: VoiceCommand = try self.decode(url, limit: 4096) else { throw BridgeError.expired }
            guard command.id == id, command.version == 1, command.lease.generation == generation,
                  command.expiresAt > Date(), command.expiresAt.timeIntervalSinceNow <= 10 else { throw BridgeError.invalidMessage }
            guard let lease = try self.lease(command.lease.id), lease.documentID == command.lease.documentID,
                  lease.generation == generation else { throw BridgeError.invalidTarget }
            try self.writeData(Data([1]), to: accepted)
            try self.files.removeItem(at: url)
            return command
        }
    }

    public func consume(_ expected: VoiceStatus, lease: KeyboardLease) throws -> String {
        guard let id = expected.requestID else { throw BridgeError.invalidTarget }
        return try coordinated("consumed-\(id).json", writing: true) { url in
            guard !self.files.fileExists(atPath: url.path) else { throw BridgeError.alreadyConsumed }
            guard let current = try self.status(), current.phase == .result,
                  current.generation == lease.generation, current.requestID == id,
                  current.leaseID == lease.id, current.documentID == lease.documentID,
                  current.expiresAt ?? .distantPast > Date(), !current.text.isEmpty,
                  try self.lease(lease.id) == lease else { throw BridgeError.invalidTarget }
            try self.writeData(Data([1]), to: url)
            _ = try self.status()
            return current.text
        }
    }

    public func isConsumed(_ id: UUID) -> Bool { files.fileExists(atPath: root.appendingPathComponent("consumed-\(id).json").path) }

    public func reset() throws {
        for url in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard url.lastPathComponent != "status.json" else { continue }
            try files.removeItem(at: url)
        }
    }

    /// The keyboard cannot wake the main app, so a standby main app polls for posted commands.
    public func pendingCommandIDs() throws -> [UUID] {
        try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("command-") && $0.pathExtension == "json" }
            .prefix(64)
            .compactMap { UUID(uuidString: String($0.deletingPathExtension().lastPathComponent.dropFirst(8))) }
    }
}
