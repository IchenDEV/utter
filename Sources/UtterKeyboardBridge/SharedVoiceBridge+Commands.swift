import Foundation

extension SharedVoiceBridge {
    public func discardCommand(_ id: UUID, lease: KeyboardLease) throws {
        try coordinated("command-\(id).json", writing: true) { url in
            guard let command: VoiceCommand = try self.decode(url, limit: Self.selectionPayloadLimit) else { return }
            guard command.id == id, command.lease.id == lease.id, command.lease.documentID == lease.documentID,
                  command.lease.generation == lease.generation else { throw BridgeError.invalidTarget }
            try self.retireCommand(command, at: url)
        }
    }

    func retireCommand(_ command: VoiceCommand, at url: URL) throws {
        try writeData(Data([1]), to: root.appendingPathComponent("accepted-\(command.id).json"))
        try files.removeItem(at: url)
    }
}
