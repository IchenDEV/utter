import Foundation

package enum GenerationTimingObservations {
    @TaskLocal package static var current: GenerationTimingObservation?
}

package final class GenerationTimingObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var timings: [GenerationTiming] = []
    private var closed = false

    package init() {}
    package func record(_ timing: GenerationTiming) {
        lock.lock(); defer { lock.unlock() }
        if !closed { timings.append(timing) }
    }
    package func finish() -> [GenerationTiming] {
        lock.lock(); defer { lock.unlock() }
        closed = true
        return timings
    }
}
