import Foundation
import XCTest
import UtterContracts
import UtterSession

@MainActor
final class VoiceModelQueueCaptureTests: XCTestCase {
    func testCaptureAndReleaseDoNotWaitForTheModelResourceLease() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let access = try fixture.runtime.service(ModelServices.resourceAccess)
        var leased = false
        var release: CheckedContinuation<Void, Never>?
        let blocker = Task {
            try await access.withAccess {
                leased = true
                await withCheckedContinuation { release = $0 }
            }
        }
        while !leased { await Task.yield() }
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local)
        try driver.start(intent)
        for _ in 0..<1_000 {
            if !fixture.capture.requests.isEmpty { break }
            await Task.yield()
        }
        XCTAssertEqual(fixture.capture.requests.count, 1)
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        XCTAssertFalse(fixture.engine.preparing)
        XCTAssertTrue(driver.requestStop(intent.id, at: nil))
        for _ in 0..<1_000 {
            if fixture.capture.recording.finished { break }
            await Task.yield()
        }
        XCTAssertTrue(fixture.capture.recording.finished)
        XCTAssertFalse(fixture.capture.recording.closed)
        release?.resume()
        try await blocker.value
        _ = try await driver.waitForCompletion(intent.id)
        XCTAssertEqual(fixture.engine.transcribed, [URL(fileURLWithPath: "/captured.wav")])
        XCTAssertTrue(fixture.capture.recording.closed)
        XCTAssertNotNil(driver.snapshot.performance?.completedInsertionMilliseconds)
        try await fixture.runtime.stop()
    }
}
