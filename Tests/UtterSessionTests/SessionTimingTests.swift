import Foundation
import XCTest
import UtterContracts
@testable import UtterSession

@MainActor
final class SessionTimingTests: XCTestCase {
    func testReleaseIncludesQueuedCallbackAndAllStagesThroughTheTerminal() async {
        var now = Duration.milliseconds(100)
        let timing = SessionTiming(now: { now })
        let preparing = timing.begin(.preparation)
        now = .milliseconds(400)
        timing.stop(at: .milliseconds(350))
        now = .milliseconds(800)
        timing.end(preparing)
        let tail = timing.begin(.tail)
        now = .milliseconds(900)
        timing.end(tail)
        let recognition = timing.begin(.transcription)
        now = .milliseconds(1_100)
        timing.end(recognition)
        timing.generations.record(GenerationTiming(stage: .primary, elapsedMilliseconds: 250, failed: false))
        timing.generations.record(GenerationTiming(stage: .factSupport, elapsedMilliseconds: 150, failed: false))
        now = .milliseconds(1_800)
        let result = timing.finish(.inserted)
        XCTAssertEqual(result.completedInsertionMilliseconds, 1_450)
        XCTAssertEqual(result.stages.first { $0.stage == .queue }?.elapsedMilliseconds, 50)
        XCTAssertEqual(result.stages.first { $0.stage == .preparation }?.elapsedMilliseconds, 700)
        XCTAssertEqual(result.stages.first { $0.stage == .tail }?.elapsedMilliseconds, 100)
        XCTAssertEqual(result.stages.first { $0.stage == .transcription }?.elapsedMilliseconds, 200)
        XCTAssertEqual(result.generations.map(\.stage), [.primary, .factSupport])
    }

    func testCopiedUncertainAndFailedEndpointsCannotBecomeInsertionSamples() async {
        for terminal in [SessionPerformance.Terminal.copied, .uncertain, .notDelivered, .failed, .cancelled, .returnedText] {
            var now = Duration.milliseconds(100)
            let timing = SessionTiming(now: { now })
            timing.stop(at: nil)
            now = .milliseconds(200)
            let result = timing.finish(terminal)
            XCTAssertEqual(result.releaseToTerminalMilliseconds, 100)
            XCTAssertNil(result.completedInsertionMilliseconds)
        }
    }

    func testRepeatedStopOrLateGenerationCannotRewriteSettledMeasurements() async {
        var now = Duration.milliseconds(100)
        let timing = SessionTiming(now: { now })
        timing.stop(at: nil)
        now = .milliseconds(200)
        timing.stop(at: nil)
        _ = timing.begin(.delivery)
        now = .milliseconds(150)
        let result = timing.finish(.inserted)
        timing.generations.record(GenerationTiming(stage: .primary, elapsedMilliseconds: 999, failed: false))
        now = .milliseconds(900)
        XCTAssertEqual(result.releaseToTerminalMilliseconds, 100)
        XCTAssertEqual(timing.finish(.failed), result)
        XCTAssertTrue(result.generations.isEmpty)
    }
}
