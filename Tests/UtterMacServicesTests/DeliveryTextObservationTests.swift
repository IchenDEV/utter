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

    func testAnyAcceptedValueConfirmsAndOnlyAcceptedValuesDo() async {
        let clock = ObservationClock()
        let viaSecond = await DeliveryTextObservation.observe(accepting: ["text+placeholder", "text"],
            read: { clock.now >= .seconds(2) ? "text" : "placeholder" }, clock: clock)
        XCTAssertTrue(viaSecond.confirmed)
        XCTAssertEqual(clock.now, .seconds(2))

        let unchanged = ObservationClock()
        let stays = await DeliveryTextObservation.observe(accepting: ["text+placeholder", "text"],
            read: { "placeholder" }, clock: unchanged)
        XCTAssertFalse(stays.confirmed)
        XCTAssertEqual(stays.lastRead, "placeholder")
        XCTAssertEqual(unchanged.now, .seconds(3))

        let other = ObservationClock()
        let different = await DeliveryTextObservation.observe(accepting: ["text"], read: { "something else" }, clock: other)
        XCTAssertFalse(different.confirmed)
        XCTAssertEqual(different.lastRead, "something else")
    }

    func testTheLastReadableValueSurvivesLaterUnreadableOnes() async {
        let clock = ObservationClock()
        let result = await DeliveryTextObservation.observe(accepting: ["text"],
            read: { clock.now < .seconds(1) ? "old" : nil }, clock: clock)
        XCTAssertFalse(result.confirmed)
        XCTAssertEqual(result.lastRead, "old")
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
