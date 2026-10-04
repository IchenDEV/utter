import Foundation
import XCTest
import UtterContracts
import UtterSession

final class SessionMetricsTests: XCTestCase {
    func testDefaultMetricsContainNoDictationOrGeneratedBodies() throws {
        let event = try XCTUnwrap(SessionMetricsEvent(SessionExecutionSnapshot(id: UUID(), phase: .completed,
            transcript: "private speech", text: "private output", deliveryStatus: .copied,
            performance: SessionPerformance(terminal: .copied, releaseToTerminalMilliseconds: 900, stages: [], generations: []))))
        let data = try JSONEncoder().encode(event)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("private speech"))
        XCTAssertFalse(text.contains("private output"))
        XCTAssertNil(event.performance.completedInsertionMilliseconds)
        XCTAssertEqual(event.performance.terminal, .copied)
    }
    func testBusyOrUnmeasuredSnapshotsCannotPublishAMetric() {
        XCTAssertNil(SessionMetricsEvent(SessionExecutionSnapshot(id: UUID(), phase: .processing, isBusy: true)))
        XCTAssertNil(SessionMetricsEvent(SessionExecutionSnapshot(id: UUID(), phase: .completed)))
    }
}
