import Foundation
import UtterContracts

@MainActor
final class SessionTiming {
    private let now: () -> Duration
    private var latest: Duration = .zero
    private var stoppedAt: Duration?
    private var active: [UUID: (SessionStage, Duration)] = [:]
    private var stages: [SessionStageTiming] = []
    let generations = GenerationTimingObservation()
    private var completed: SessionPerformance?

    init(now: @escaping () -> Duration) { self.now = now }

    func begin(_ stage: SessionStage) -> UUID {
        let id = UUID()
        active[id] = (stage, sample())
        return id
    }

    func end(_ id: UUID) {
        guard let (stage, start) = active.removeValue(forKey: id) else { return }
        stages.append(SessionStageTiming(stage: stage, elapsedMilliseconds: milliseconds(sample() - start)))
    }

    func stop(at eventTimestamp: Duration?) {
        guard stoppedAt == nil else { return }
        let callbackTime = sample()
        let eventTime = min(eventTimestamp ?? callbackTime, callbackTime)
        stoppedAt = eventTime
        stages.append(SessionStageTiming(stage: .queue, elapsedMilliseconds: milliseconds(callbackTime - eventTime)))
    }

    func finish(_ terminal: SessionPerformance.Terminal) -> SessionPerformance {
        if let completed { return completed }
        let end = sample()
        for (_, (stage, start)) in active {
            stages.append(SessionStageTiming(stage: stage, elapsedMilliseconds: milliseconds(end - start)))
        }
        active.removeAll()
        let result = SessionPerformance(terminal: terminal,
            releaseToTerminalMilliseconds: stoppedAt.map { milliseconds(end - $0) },
            stages: stages, generations: generations.finish())
        completed = result
        return result
    }

    private func sample() -> Duration {
        latest = max(latest, now())
        return latest
    }
}
