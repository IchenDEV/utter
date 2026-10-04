import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterRuntime
@testable import UtterSession

@MainActor
final class SessionDriverTests: XCTestCase {
    func testEveryEntryWaitsForCancellationAndResourceDrain() async throws {
        let fixture = try DriverFixture()
        defer { fixture.remove() }
        let job = HeldSessionJob()
        let factory = DriverFactory(job: job)
        let driver = fixture.driver(factory)
        try driver.start(SessionIntent(input: .local))
        while !job.entered { await Task.yield() }
        driver.cancel()
        for input in [SessionInput.remote(token: 1), .file(URL(fileURLWithPath: "/borrowed.wav")), .local] {
            XCTAssertThrowsError(try driver.start(SessionIntent(clientID: "api", input: input))) {
                XCTAssertEqual($0 as? IntegrationError, .busy)
            }
        }
        job.release()
        while !job.closing { await Task.yield() }
        XCTAssertTrue(driver.snapshot.isBusy)
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .local)))
        job.finishClose()
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(driver.snapshot.phase, .cancelled)
        XCTAssertEqual(fixture.history.records.count, 0)
        await driver.close()
    }

    func testAcceptedDeliveryStillSettlesOnceAfterCancellationAndBeforeNotifications() async throws {
        let fixture = try DriverFixture()
        defer { fixture.remove() }
        let job = HeldSessionJob()
        job.accepted = true
        let factory = DriverFactory(job: job)
        let driver = fixture.driver(factory)
        let intent = SessionIntent(input: .remote(token: 7))
        try driver.start(intent)
        while !job.entered { await Task.yield() }
        driver.cancel()
        var notifications = 0
        _ = fixture.history.observe {
            XCTAssertTrue(factory.settled)
            XCTAssertFalse(driver.snapshot.isBusy)
            XCTAssertEqual(driver.snapshot.phase, .completed)
            XCTAssertEqual(fixture.history.records.map(\.id), [intent.id])
            notifications += 1
        }
        job.release()
        while !job.closing { await Task.yield() }
        XCTAssertEqual(notifications, 0)
        job.finishClose()
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(notifications, 1)
        XCTAssertThrowsError(try driver.start(intent)) { XCTAssertEqual($0 as? IntegrationError, .invalidSessionState) }
        await driver.close()
        XCTAssertEqual(fixture.history.records.count, 1)
    }

    func testUncertainDeliveryKeepsExplicitCopyTextWithoutHistoryOrAutomaticReplay() async throws {
        let fixture = try DriverFixture()
        defer { fixture.remove() }
        let job = HeldSessionJob()
        job.accepted = true
        job.disposition = .uncertain
        let factory = DriverFactory(job: job)
        let driver = fixture.driver(factory)
        let intent = SessionIntent(input: .local)
        try driver.start(intent)
        while !job.entered { await Task.yield() }
        job.release()
        while !job.closing { await Task.yield() }
        job.finishClose()
        while driver.snapshot.isBusy { await Task.yield() }
        XCTAssertEqual(driver.snapshot.phase, .failed)
        XCTAssertEqual(driver.snapshot.text, "accepted")
        XCTAssertTrue(fixture.history.records.isEmpty)
        XCTAssertEqual(factory.constructed, 1)
        XCTAssertThrowsError(try driver.start(intent))
        await driver.close()
    }

    func testScopedExecutionDrainsBeforeItsWorkflowDependencyIsDisposed() async throws {
        let fixture = try DriverFixture()
        defer { fixture.remove() }
        let suite = "driver-runtime-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let job = HeldSessionJob()
        let factory = DriverFactory(job: job)
        var dependencyDisposed = false
        let workflows = PluginRegistration(descriptor: PluginDescriptor(id: "replacement.workflows", provides: [SessionServices.workflows.reference])) { context, _ in
            try context.scope.onDispose { dependencyDisposed = true }
            try context.provide(SessionServices.workflows, value: factory)
        }
        let plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.notifications(),
                       DataPlugins.history(directoryURL: fixture.directory, reportError: { _ in }),
                       workflows, SessionPlugins.execution()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        let driver = try runtime.service(SessionServices.execution)
        try driver.start(SessionIntent(input: .local))
        while !job.entered { await Task.yield() }
        let stop = Task { try await runtime.stop() }
        job.release()
        while !job.closing { await Task.yield() }
        XCTAssertFalse(dependencyDisposed)
        job.finishClose()
        try await stop.value
        XCTAssertTrue(dependencyDisposed)
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .local)))
    }

    func testRegistrationReadinessAndRevocationPreventWorkConstruction() async throws {
        let fixture = try DriverFixture()
        defer { fixture.remove() }
        let factory = DriverFactory(job: HeldSessionJob())
        var ready = false
        let driver = SessionDriver(workflows: factory, history: fixture.history,
                                   notifications: fixture.notifications, isReady: { ready })
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .local)))
        ready = true
        driver.revoke()
        XCTAssertThrowsError(try driver.start(SessionIntent(input: .local)))
        XCTAssertEqual(factory.constructed, 0)
        await driver.close()
    }
}

@MainActor
private struct DriverFixture {
    let directory: URL
    let notifications = StateNotifications()
    let history: HistoryStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        history = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in }, notifications: notifications)
    }
    func driver(_ factory: DriverFactory) -> SessionDriver {
        SessionDriver(workflows: factory, history: history, notifications: notifications)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class DriverFactory: SessionWorkflowFactory {
    let job: HeldSessionJob
    var constructed = 0
    var settled = false
    init(job: HeldSessionJob) { self.job = job }
    func make(_ intent: SessionIntent) throws -> any SessionJob { constructed += 1; return job }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) { settled = true }
}

@MainActor
private final class HeldSessionJob: SessionJob {
    var entered = false
    var closing = false
    var accepted = false
    var disposition = DeliveryDisposition.accepted
    private var waiter: CheckedContinuation<Void, Never>?
    private var closeWaiter: CheckedContinuation<Void, Never>?
    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        entered = true
        control.update(phase: .recording, transcript: "")
        await withCheckedContinuation { waiter = $0 }
        if !accepted { throw CancellationError() }
        return SessionCompletion(transcript: "raw", text: "accepted", acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: disposition, effect: .paste)
        ), record: InputRecord(rawText: "raw", processedText: "accepted", wasProcessed: true))
    }
    func revoke() {}
    func close() async {
        closing = true
        await withCheckedContinuation { closeWaiter = $0 }
    }
    func release() { waiter?.resume(); waiter = nil }
    func finishClose() { closeWaiter?.resume(); closeWaiter = nil }
}
