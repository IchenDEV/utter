import Foundation
import XCTest
import UtterContracts
import UtterData
@testable import UtterSession

@MainActor
final class SessionDriverInputBindingTests: XCTestCase {
    func testOnlyInputOperationsBindALocalSourceToAnUnselectedIntent() async throws {
        let cases: [(SessionOperation, [SessionInput])] = [
            (.input, [.local]),
            (.copy("Desktop copy"), []),
            (.applyReplacement(UUID()), []),
        ]
        for (operation, expectedBindings) in cases {
            let notifications = StateNotifications()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let history = HistoryStore(directoryURL: directory, retention: { .forever },
                                       reportError: { _ in }, notifications: notifications)
            let job = BindingJob(acceptsBinding: operation == .input)
            let driver = SessionDriver(workflows: BindingFactory(job: job), history: history, notifications: notifications)

            let intent = SessionIntent(input: .unselected, operation: operation)
            try driver.start(intent)
            let snapshot = try await driver.waitForCompletion(intent.id)

            XCTAssertEqual(snapshot.phase, .completed, "\(operation)")
            XCTAssertEqual(job.boundInputs, expectedBindings, "\(operation)")
            await driver.close()
        }
    }
}

@MainActor
private final class BindingFactory: SessionWorkflowFactory {
    let job: BindingJob
    init(job: BindingJob) { self.job = job }
    func make(_ intent: SessionIntent) throws -> any SessionJob { job }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {}
}

@MainActor
private final class BindingJob: SessionJob {
    private(set) var boundInputs: [SessionInput] = []
    private let acceptsBinding: Bool
    init(acceptsBinding: Bool) { self.acceptsBinding = acceptsBinding }

    // Mirrors the protocol default for jobs that take no input source.
    func bind(input: SessionInput) throws {
        boundInputs.append(input)
        if !acceptsBinding { throw IntegrationError.invalidSessionState }
    }

    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        SessionCompletion(transcript: "", text: "text", acceptance: .delivery(DeliveryReceipt(
            operationID: UUID(), disposition: .accepted, effect: .clipboard, confirmation: .clipboardValue)),
            outputMutation: .preserve)
    }
    func revoke() {}
    func close() async {}
}
