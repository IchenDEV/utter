import Foundation

/// Holds decoded audio that arrives before the recording pipeline is ready.
///
/// The remote can deliver `AUDIO_START`/audio frames in the same run loop as the
/// control event, but the pipeline that consumes them starts asynchronously. A
/// bounded pre-roll keeps the first moments so the opening word is not clipped,
/// and drops the oldest data once the bound is hit so a session that never
/// starts cannot grow without limit.
struct RemoteMicPreRoll {
    /// Thirty seconds of 16 kHz mono audio is under 1 MB as `Int16` samples and
    /// covers a normal cold model load without clipping the beginning.
    static let defaultFrameCapacity = 16_000 * 30

    private let frameCapacity: Int
    private var chunks: [[Int16]] = []
    private var frameCount = 0

    init(frameCapacity: Int = Self.defaultFrameCapacity) {
        self.frameCapacity = max(1, frameCapacity)
    }

    var isEmpty: Bool { chunks.isEmpty }
    var retainedChunks: Int { chunks.count }
    var retainedFrames: Int { frameCount }

    mutating func append(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        chunks.append(samples)
        frameCount += samples.count
        while frameCount > frameCapacity, chunks.count > 1 {
            frameCount -= chunks.removeFirst().count
        }
        if frameCount > frameCapacity, let last = chunks.last {
            chunks = [Array(last.suffix(frameCapacity))]
            frameCount = chunks[0].count
        }
    }

    /// Returns the retained audio in order and empties the buffer.
    mutating func drain() -> [[Int16]] {
        let drained = chunks
        chunks.removeAll(keepingCapacity: false)
        frameCount = 0
        return drained
    }

    mutating func reset() {
        chunks.removeAll(keepingCapacity: false)
        frameCount = 0
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
