import Foundation

final class StreamingCapturePlan: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedEarlyAudio = false
    private var streaming = false
    private var finished = false

    func receiveBuffer() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return false }
        if !streaming { receivedEarlyAudio = true }
        return streaming
    }

    func beginStreaming() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !receivedEarlyAudio, !finished else { return false }
        streaming = true
        return true
    }

    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        finished = true
        return streaming
    }
}
