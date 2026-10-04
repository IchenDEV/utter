import Foundation
import XCTest
@testable import UtterContracts

final class PermissionRequestTests: XCTestCase {
    func testPermissionUsesActualResponseIncludingDenial() async throws {
        let allowed = try await PermissionRequest.wait { $0(true) }
        let denied = try await PermissionRequest.wait { $0(false) }
        XCTAssertTrue(allowed)
        XCTAssertFalse(denied)
    }

    func testCancellationReturnsWithoutWaitingForSystemPromptAndIgnoresLateResponses() async throws {
        let probe = PermissionProbe()
        let task = Task { try await PermissionRequest.wait(start: probe.start) }
        while !probe.entered { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled permission returned a grant") }
        catch { XCTAssertTrue(error is CancellationError) }
        probe.respond(true)
        probe.respond(false)
    }

    func testCancellationBeforeEntryDoesNotLaunchPermissionPrompt() async {
        let probe = PermissionProbe()
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await PermissionRequest.wait(start: probe.start)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request launched") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(probe.entered)
    }
}

private final class PermissionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (Bool) -> Void)?
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return callback != nil }
    func start(_ callback: @escaping @Sendable (Bool) -> Void) {
        lock.lock(); defer { lock.unlock() }; self.callback = callback
    }
    func respond(_ value: Bool) {
        lock.lock(); let callback = callback; lock.unlock()
        callback?(value)
    }
}
