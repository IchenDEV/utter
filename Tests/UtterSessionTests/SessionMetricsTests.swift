import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterRuntime
import UtterSession

final class SessionMetricsTests: XCTestCase {
    @MainActor
    func testMountedMetricsObserveTheEffectiveExecutionAndStopWithItsScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Metrics-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let diagnostics = MetricsDiagnostics()
        let workflows = PluginRegistration(descriptor: PluginDescriptor(id: "test.workflows",
            provides: [SessionServices.workflows.reference])) { context, _ in
            try context.provide(SessionServices.workflows, value: MetricsFactory())
        }
        let plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.notifications(),
            DataPlugins.history(directoryURL: directory, reportError: { _ in }), DataPlugins.diagnostics(diagnostics),
            workflows, SessionPlugins.execution(), SessionPlugins.metrics()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        let execution = try runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .text("private speech"))
        try execution.start(intent)
        _ = try await execution.waitForCompletion(intent.id)
        XCTAssertEqual(diagnostics.messages.count, 1)
        XCTAssertTrue(diagnostics.messages[0].contains("returnedText"))
        XCTAssertFalse(diagnostics.messages[0].contains("private speech"))
        XCTAssertFalse(diagnostics.messages[0].contains("private output"))
        try await runtime.stop()
        XCTAssertThrowsError(try execution.start(SessionIntent(input: .text("later"))))
        XCTAssertEqual(diagnostics.messages.count, 1)
    }
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

private final class MetricsDiagnostics: DiagnosticsService, @unchecked Sendable {
    var messages: [String] = []
    func info(_ message: String) { messages.append(message) }
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
@MainActor
private final class MetricsFactory: SessionWorkflowFactory {
    func make(_ intent: SessionIntent) throws -> any SessionJob { MetricsJob() }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {}
}
@MainActor
private final class MetricsJob: SessionJob {
    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        SessionCompletion(transcript: "private speech", text: "private output", acceptance: .returnedText)
    }
    func revoke() {}
    func close() async {}
}
