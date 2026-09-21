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
