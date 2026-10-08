import Foundation

@MainActor
protocol DeliveryObservationClock {
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}

@MainActor
final class ContinuousDeliveryClock: DeliveryObservationClock {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now
    var now: Duration { origin.duration(to: clock.now) }
    func sleep(for duration: Duration) async throws { try await clock.sleep(for: duration) }
}

@MainActor
enum DeliveryTextObservation {
    static func confirm(_ expected: String, read: () -> String?, clock: any DeliveryObservationClock,
                        timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = clock.now + timeout
        repeat {
            if read() == expected { return true }
            guard clock.now < deadline else { return false }
            do { try await clock.sleep(for: min(.milliseconds(25), deadline - clock.now)) }
            catch { return false }
        } while true
    }
}
