import XCTest
@testable import UtterMacServices

@MainActor
final class DeliveryTextObservationTests: XCTestCase {
    func testSlowConsumptionAndThreeSecondTimeoutUseMonotonicClock() async {
        let slow = ObservationClock()
        let confirmed = await DeliveryTextObservation.confirm("new", read: { slow.now >= .milliseconds(500) ? "new" : "old" }, clock: slow)
        XCTAssertTrue(confirmed)
        XCTAssertEqual(slow.now, .milliseconds(500))
        let expired = ObservationClock()
        let failed = await DeliveryTextObservation.confirm("new", read: { "old" }, clock: expired)
        XCTAssertFalse(failed)
        XCTAssertEqual(expired.now, .seconds(3))
    }

    func testUnavailableValueAndSleepFailureCannotConfirmInsertion() async {
        let clock = ObservationClock()
        clock.failsSleep = true
        let confirmed = await DeliveryTextObservation.confirm("new", read: { nil }, clock: clock)
        XCTAssertFalse(confirmed)
    }
}

@MainActor
private final class ObservationClock: DeliveryObservationClock {
    var now: Duration = .zero
    var failsSleep = false
    func sleep(for duration: Duration) async throws {
        if failsSleep { throw CancellationError() }
        now += duration
    }
}
