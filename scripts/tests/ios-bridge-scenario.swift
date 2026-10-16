import Foundation

@main
struct BridgeScenario {
    @MainActor
    static func main() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: container) }
        let keyboard = try SharedVoiceBridge(container: container)
        let host = try SharedVoiceBridge(container: container)
        var status = VoiceStatus(phase: .ready)
        try host.publish(status)
        let lease = KeyboardLease(generation: status.generation, documentID: UUID())
        try keyboard.renew(lease)
        let start = VoiceCommand(lease: lease, action: .start)
        try keyboard.post(start)
        let admitted = try host.take(start.id, generation: status.generation)
        precondition(admitted.lease == lease)
        try keyboard.post(start)
        try rejects(.alreadyConsumed) { _ = try host.take(start.id, generation: status.generation) }

        status.phase = .result; status.requestID = start.id; status.leaseID = lease.id
        status.documentID = lease.documentID; status.text = "Private fixture"; status.expiresAt = Date().addingTimeInterval(120)
        try host.publish(status)
        let wrong = KeyboardLease(generation: status.generation, documentID: UUID())
        try keyboard.renew(wrong)
        try rejects(.invalidTarget) { _ = try keyboard.consume(status, lease: wrong) }
        let root = container.appendingPathComponent("UtterVoice-v1")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        do {
            _ = try keyboard.consume(status, lease: lease)
            preconditionFailure("Receipt failure must prevent submission")
        } catch {}
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        precondition(!keyboard.isConsumed(start.id))
        let submitted = try keyboard.consume(status, lease: lease)
        precondition(submitted == status.text)
        try rejects(.alreadyConsumed) { _ = try keyboard.consume(status, lease: lease) }
        let restarted = try SharedVoiceBridge(container: container)
        try rejects(.alreadyConsumed) { _ = try restarted.consume(status, lease: lease) }
        let consumedStatus = try host.status()
        precondition(consumedStatus?.text == "")
        let bytes = try Data(contentsOf: container.appendingPathComponent("UtterVoice-v1/status.json"))
        precondition(!String(decoding: bytes, as: UTF8.self).contains("Private fixture"))

        status.requestID = UUID(); status.expiresAt = .distantPast
        try host.publish(status)
        let expiredStatus = try keyboard.status()
        precondition(expiredStatus?.text == "")
        let expiredBytes = try Data(contentsOf: container.appendingPathComponent("UtterVoice-v1/status.json"))
        precondition(!String(decoding: expiredBytes, as: UTF8.self).contains("Private fixture"))

        let late = VoiceCommand(lease: lease, action: .start)
        try keyboard.post(late); try keyboard.revoke(lease.id)
        try rejects(.invalidTarget) { _ = try host.take(late.id, generation: status.generation) }
        try keyboard.renew(lease)
        let stale = VoiceCommand(lease: lease, action: .start)
        try keyboard.post(stale)
        try rejects(.invalidMessage) { _ = try host.take(stale.id, generation: UUID()) }

        let oversizedID = UUID()
        let url = container.appendingPathComponent("UtterVoice-v1/command-\(oversizedID).json")
        try Data(repeating: 65, count: 4097).write(to: url)
        try rejects(.tooLarge) { _ = try host.take(oversizedID, generation: status.generation) }
        try Data("{}".utf8).write(to: url)
        try rejects(.invalidMessage) { _ = try host.take(oversizedID, generation: status.generation) }
        var expiredLease = lease; expiredLease.expiresAt = .distantPast
        try rejects(.expired) { try keyboard.renew(expiredLease) }
        try host.reset()
        let removedLease = try host.lease(lease.id)
        precondition(removedLease == nil)
        print("Bridge scenario passed: admission, replay, document change, receipt failure, restart without replay, cleanup, expiry, generation, limits and malformed messages")
    }

    @MainActor
    private static func rejects(_ expected: BridgeError, operation: () throws -> Void) throws {
        do { try operation(); preconditionFailure("Unexpected acceptance") }
        catch let error as BridgeError { precondition(error == expected) }
    }
}
