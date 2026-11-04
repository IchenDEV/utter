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
    struct Result {
        let confirmed: Bool
        /// Last value that could be read, kept only so a failure can be described by counts. Never logged as text.
        let lastRead: String?
    }

    static func confirm(_ expected: String, read: () -> String?, clock: any DeliveryObservationClock,
                        timeout: Duration = .seconds(3)) async -> Bool {
        await observe(accepting: [expected], read: read, clock: clock, timeout: timeout).confirmed
    }

    static func observe(accepting accepted: [String], read: () -> String?, clock: any DeliveryObservationClock,
                        timeout: Duration = .seconds(3)) async -> Result {
        let deadline = clock.now + timeout
        var lastRead: String?
        repeat {
            let value = read()
            if let value { lastRead = value }
            if let value, accepted.contains(value) { return Result(confirmed: true, lastRead: lastRead) }
            guard clock.now < deadline else { return Result(confirmed: false, lastRead: lastRead) }
            do { try await clock.sleep(for: min(.milliseconds(25), deadline - clock.now)) }
            catch { return Result(confirmed: false, lastRead: lastRead) }
        } while true
    }
}
