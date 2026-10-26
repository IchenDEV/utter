import Foundation
import XCTest
import UtterBuiltins
import UtterContracts
import UtterRuntime

@MainActor
final class ApplicationShutdownTests: XCTestCase {
    private struct Injected: Error {}

    private final class ErrorLog: DiagnosticsService, @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [String] = []
        var messages: [String] { lock.withLock { errors } }

        func info(_ message: String) {}
        func sensitive(_ message: String) {}
        func error(_ message: String) { lock.withLock { errors.append(message) } }
    }

    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }

        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }

    @MainActor
    private final class Flag { var isSet = false }

    private func start(_ plugin: PluginRegistration) async throws -> (BuiltinApplication, cleanup: () -> Void) {
        let suite = "ApplicationShutdown-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The legacy settings layer binds speech and text providers, which must be mounted; empty
        // stand-ins keep the graph to the recovery plugins plus the one under test.
        let standIns = ["speech.apple", "generation.mlx"].map { PluginRegistration(descriptor: PluginDescriptor(id: $0)) { _, _ in } }
        let rows = (standIns.map(\.descriptor.id) + [plugin.descriptor.id]).map { #"{"id":"\#($0)"}"# }.joined(separator: ",")
        let document = #"{"schemaVersion":1,"bundles":["recovery"],"plugins":[\#(rows)]}"#
        try Data(document.utf8).write(to: directory.appendingPathComponent("plugins.json"))
        let application = try await BuiltinApplication.start(defaults: defaults, directory: directory,
            additional: [plugin], replacements: standIns)
        XCTAssertNil(application.compositionFailure)
        XCTAssertTrue(application.runtime.pendingDisposalPluginIDs.contains(plugin.descriptor.id))
        return (application, {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    func testStalledDisposalReturnsWithinTheBoundAndNamesThePlugin() async throws {
        let gate = Gate()
        let revoked = Flag()
        let (application, cleanup) = try await start(PluginRegistration(descriptor: PluginDescriptor(id: "test.stalled")) { context, _ in
            try context.scope.onRevoke { revoked.isSet = true }
            try context.scope.onDispose { await gate.wait() }
        })
        defer { cleanup() }
        let log = ErrorLog()
        let started = ContinuousClock.now
        await ApplicationShutdown.run(startup: nil, application: { application }, limit: .milliseconds(200), log: Log(service: log))
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(10))
        XCTAssertTrue(revoked.isSet, "Revocation must have run before the process is allowed to exit")
        XCTAssertEqual(log.messages.count, 1)
        let message = try XCTUnwrap(log.messages.first)
        XCTAssertTrue(message.hasPrefix("Shutdown exceeded 0.2s; disposing: test.stalled; pending: ["), message)
        XCTAssertTrue(message.contains("test.stalled"), message)

        while !gate.isWaiting { await Task.yield() }
        gate.release()
        for _ in 0..<20 { await Task.yield() }
    }

    func testThrowingDisposalIsLoggedWithIdsAndReturns() async throws {
        let (application, cleanup) = try await start(PluginRegistration(descriptor: PluginDescriptor(id: "test.throwing")) { context, _ in
            try context.scope.onDispose { throw Injected() }
        })
        defer { cleanup() }
        let log = ErrorLog()
        await ApplicationShutdown.run(startup: nil, application: { application }, log: Log(service: log))
        let message = try XCTUnwrap(log.messages.first)
        XCTAssertTrue(message.hasPrefix("Shutdown failed: test.throwing (") && message.contains("Injected"), message)
        XCTAssertEqual(log.messages.count, 1)
    }

    func testHealthyDrainIsNotGatedByTheTimerAndLogsNothing() async throws {
        let (application, cleanup) = try await start(PluginRegistration(descriptor: PluginDescriptor(id: "test.healthy")) { context, _ in
            try context.scope.onDispose {}
        })
        defer { cleanup() }
        let log = ErrorLog()
        await ApplicationShutdown.run(startup: nil, application: { application },
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, log: Log(service: log))
        XCTAssertEqual(log.messages, [])
        XCTAssertEqual(application.runtime.state, .stopped)
    }

    func testStartupThatNeverFinishesIsBoundedToo() async {
        let gate = Gate()
        let startup = Task { await gate.wait() }
        let log = ErrorLog()
        await ApplicationShutdown.run(startup: startup, application: { nil }, limit: .milliseconds(100), log: Log(service: log))
        XCTAssertEqual(log.messages, ["Shutdown exceeded 0.1s before startup finished"])
        while !gate.isWaiting { await Task.yield() }
        gate.release()
        await startup.value
    }

    func testTheBoundIsFiveSeconds() {
        XCTAssertEqual(ApplicationShutdown.limit, .seconds(5))
    }
}
