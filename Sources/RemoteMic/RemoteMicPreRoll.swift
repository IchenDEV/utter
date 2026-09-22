import Foundation

/// Holds decoded audio that arrives before the recording pipeline is ready.
///
/// The remote can deliver `AUDIO_START`/audio frames in the same run loop as the
/// control event, but the pipeline that consumes them starts asynchronously. A
/// bounded pre-roll keeps the first moments so the opening word is not clipped,
/// and drops the oldest data once the bound is hit so a session that never
/// starts cannot grow without limit.
struct RemoteMicPreRoll {
    private let capacity: Int
    private var chunks: [[Int16]] = []
    private var chunkCount = 0

    init(capacity: Int = 4) {
        self.capacity = max(1, capacity)
    }

    var isEmpty: Bool { chunks.isEmpty }
    var retainedChunks: Int { chunks.count }
    var retainedFrames: Int { chunkCount }

    mutating func append(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        chunks.append(samples)
        chunkCount += samples.count
        while chunks.count > capacity {
            chunkCount -= chunks.removeFirst().count
        }
    }

    /// Returns the retained audio in order and empties the buffer.
    mutating func drain() -> [[Int16]] {
        let drained = chunks
        chunks.removeAll(keepingCapacity: false)
        chunkCount = 0
        return drained
    }

    mutating func reset() {
        chunks.removeAll(keepingCapacity: false)
        chunkCount = 0
    }
}

/// Where a decoded audio chunk belongs, given the session phase.
///
/// Extracted so the bridge's routing is the exact rule a test exercises: audio
/// with no live session (before a press, or late after a stop) is dropped so it
/// cannot pollute the next session's pre-roll.
enum RemoteMicAudioRouting {
    enum Destination: Equatable {
        case forward
        case preRoll
        case drop
    }

    static func destination(for phase: RemoteMicSession.Phase) -> Destination {
        switch phase {
        case .recording: return .forward
        case .starting: return .preRoll
        case .idle: return .drop
        }
    }
}
