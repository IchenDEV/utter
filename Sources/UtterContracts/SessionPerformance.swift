import Foundation

package enum GenerationStage: String, Codable, Sendable { case primary, fallback, factSupport, image }
package struct GenerationTiming: Codable, Equatable, Sendable {
    package let stage: GenerationStage
    package let elapsedMilliseconds: Double
    package let failed: Bool
    package init(stage: GenerationStage, elapsedMilliseconds: Double, failed: Bool) {
        self.stage = stage
        self.elapsedMilliseconds = elapsedMilliseconds.isFinite ? max(0, elapsedMilliseconds) : 0
        self.failed = failed
    }
}

package enum SessionStage: String, Codable, Sendable {
    case queue, preparation, tail, transcription, processing, delivery
}
package struct SessionStageTiming: Codable, Equatable, Sendable {
    package let stage: SessionStage
    package let elapsedMilliseconds: Double
    package init(stage: SessionStage, elapsedMilliseconds: Double) {
        self.stage = stage
        self.elapsedMilliseconds = elapsedMilliseconds.isFinite ? max(0, elapsedMilliseconds) : 0
    }
}

package struct SessionPerformance: Codable, Equatable, Sendable {
    package enum Terminal: String, Codable, Sendable {
        case inserted, copied, uncertain, notDelivered, returnedText, cancelled, failed
    }
    package let terminal: Terminal
    package let releaseToTerminalMilliseconds: Double?
    package let stages: [SessionStageTiming]
    package let generations: [GenerationTiming]
    package var completedInsertionMilliseconds: Double? {
        terminal == .inserted ? releaseToTerminalMilliseconds : nil
    }
    package init(terminal: Terminal, releaseToTerminalMilliseconds: Double?,
                 stages: [SessionStageTiming], generations: [GenerationTiming]) {
        self.terminal = terminal
        self.releaseToTerminalMilliseconds = releaseToTerminalMilliseconds.flatMap { $0.isFinite ? max(0, $0) : nil }
        self.stages = stages; self.generations = generations
    }
}

package func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
}
