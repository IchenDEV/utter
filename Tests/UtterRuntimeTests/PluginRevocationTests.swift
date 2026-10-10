import XCTest
@testable import UtterRuntime

@MainActor
final class PluginRevocationTests: XCTestCase {
    func testRevocationRunsOnceBeforeDisposalAndRejectsLateRegistration() async throws {
        let scope = PluginScope(pluginID: "fixture")
        var events: [String] = []
        try scope.onRevoke { events.append("first") }
        try scope.onRevoke { events.append("second") }
        try scope.onDispose { events.append("dispose") }
        XCTAssertTrue(events.isEmpty)
        scope.revoke()
        XCTAssertEqual(events, ["second", "first"])
        XCTAssertThrowsError(try scope.onRevoke { events.append("late") })
        _ = await scope.dispose()
        _ = await scope.dispose()
        XCTAssertEqual(events, ["second", "first", "dispose"])
    }

    func testRuntimeRevokesAllIngressBeforeWaitingForDependentCleanup() async throws {
        let key = ServiceKey<Int>("fixture.dependency")
        let barrier = RevocationBarrier()
        var dependencyRevoked = false
        var dependentRevoked = false
        let dependency = PluginRegistration(descriptor: PluginDescriptor(id: "dependency", provides: [key.reference])) { context, _ in
            try context.scope.onRevoke { dependencyRevoked = true }
            try context.provide(key, value: 1)
        }
        let dependent = PluginRegistration(descriptor: PluginDescriptor(id: "dependent", requires: [key.required])) { context, _ in
            _ = try context.require(key)
            try context.scope.onRevoke { dependentRevoked = true }
            try context.scope.onDispose { await barrier.hold() }
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([dependency, dependent]))
        try await runtime.start([PluginSelection("dependent"), PluginSelection("dependency")])
        let stop = Task { try await runtime.stop() }
        await barrier.waitUntilHeld()
        XCTAssertTrue(dependencyRevoked)
        XCTAssertTrue(dependentRevoked)
        XCTAssertEqual(runtime.state, .stopping)
        await barrier.release()
        try await stop.value
        XCTAssertEqual(runtime.state, .stopped)
    }
}

private actor RevocationBarrier {
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }
    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { held?.resume(); held = nil }
}
