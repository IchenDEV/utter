import XCTest
@testable import UtterRuntime

@MainActor
final class PluginLifecycleTests: XCTestCase {
    func testFailureAfterEachAcquiredEffectUnwindsExactlyOnce() async throws {
        enum Failure: Error { case injected }
        for failurePoint in 0...4 {
            var cleaned: [Int] = []
            let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "effects")) { context, _ in
                for effect in 0..<failurePoint {
                    try context.scope.onDispose { cleaned.append(effect) }
                }
                throw Failure.injected
            }
            let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
            do { try await runtime.start([PluginSelection("effects")]); XCTFail("Failure was ignored") }
            catch {}
            try await runtime.stop()
            XCTAssertEqual(cleaned, Array((0..<failurePoint).reversed()))
        }
    }

    func testThrowingCleanupDoesNotSkipOtherEffectsAndBlocksRestartUntilRetried() async throws {
        enum Failure: Error { case injected }
        var trace: [String] = []
        var shouldFail = true
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "effects")) { context, _ in
            try context.scope.onDispose { trace.append("first") }
            try context.scope.onDispose {
                trace.append("second")
                if shouldFail { throw Failure.injected }
            }
            try context.scope.onDispose { trace.append("third") }
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        try await runtime.start([PluginSelection("effects")])
        do { try await runtime.stop(); XCTFail("Cleanup failure was ignored") }
        catch { XCTAssertEqual((error as? PluginShutdownFailure)?.failures.count, 1) }
        XCTAssertEqual(trace, ["third", "second", "first"])
        do { try await runtime.start([PluginSelection("effects")]); XCTFail("Undisposed resources were forgotten") }
        catch { XCTAssertEqual(error as? PluginRuntimeError, .cleanupPending) }
        shouldFail = false
        try await runtime.stop()
        XCTAssertEqual(trace, ["third", "second", "first", "second"])
        XCTAssertEqual(runtime.state, .stopped)
    }

    func testShutdownWaitsForNonCooperativeWorkAndRejectsIngress() async throws {
        var resume: CheckedContinuation<Void, Never>?
        var began: CheckedContinuation<Void, Never>?
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "task")) { context, _ in
            try context.scope.task {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    began?.resume()
                }
            }
            await withCheckedContinuation { continuation in
                if resume != nil { continuation.resume() } else { began = continuation }
            }
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        try await runtime.start([PluginSelection("task")])
        let stopping = Task { try await runtime.stop() }
        while runtime.state == .ready { await Task.yield() }
        XCTAssertEqual(runtime.state, .stopping)
        XCTAssertThrowsError(try runtime.service(ServiceKey<Int>("missing")))
        do { try await runtime.start([PluginSelection("task")]); XCTFail("Started while draining") }
        catch { XCTAssertEqual(error as? PluginRuntimeError, .transitionInProgress) }
        resume?.resume()
        try await stopping.value
        XCTAssertEqual(runtime.state, .stopped)
    }

    func testCancelledActivationCannotPublishReadiness() async throws {
        var resume: CheckedContinuation<Void, Never>?
        var cleaned = false
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "delayed")) { context, _ in
            try context.scope.onDispose { cleaned = true }
            await withCheckedContinuation { resume = $0 }
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        let starting = Task { try await runtime.start([PluginSelection("delayed")]) }
        while resume == nil { await Task.yield() }
        starting.cancel()
        resume?.resume()
        do { try await starting.value; XCTFail("Cancelled boot became ready") }
        catch { XCTAssertTrue((error as? PluginActivationFailure)?.cause is CancellationError) }
        XCTAssertTrue(cleaned)
        XCTAssertEqual(runtime.state, .failed)
        try await runtime.stop()
    }

    func testContributionsAreScopedAndDuplicateIDsRejected() async throws {
        let registry = ContributionRegistry<String>()
        let scope = PluginScope(pluginID: "provider")
        try registry.contribute("speech", value: "first", scope: scope)
        XCTAssertThrowsError(try registry.contribute("speech", value: "second", scope: scope))
        XCTAssertEqual(registry.value(for: "speech"), "first")
        let failures = await scope.dispose()
        XCTAssertTrue(failures.isEmpty)
        XCTAssertNil(registry.value(for: "speech"))
        XCTAssertThrowsError(try registry.contribute("speech", value: "stale", scope: scope))
    }

    func testAsyncAcquisitionCompletingAfterCancellationStillReleasesItsResource() async throws {
        var resume: CheckedContinuation<Int, Never>?
        var released: [Int] = []
        let plugin = PluginRegistration(descriptor: PluginDescriptor(id: "acquire")) { context, _ in
            _ = try await context.scope.acquire({
                await withCheckedContinuation { resume = $0 }
            }, dispose: { value in
                try Task.checkCancellation()
                released.append(value)
            })
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([plugin]))
        let starting = Task { try await runtime.start([PluginSelection("acquire")]) }
        while resume == nil { await Task.yield() }
        starting.cancel()
        resume?.resume(returning: 7)
        do { try await starting.value; XCTFail("Cancelled acquisition became ready") }
        catch {
            XCTAssertTrue((error as? PluginActivationFailure)?.cleanupFailures.isEmpty == true)
        }
        XCTAssertEqual(released, [7])
        try await runtime.stop()
    }

    func testClosedScopeDoesNotLaunchNewTasks() async throws {
        let scope = PluginScope(pluginID: "closed")
        _ = await scope.dispose()
        var ran = false
        XCTAssertThrowsError(try scope.task { ran = true })
        await Task.yield()
        XCTAssertFalse(ran)
    }
}
