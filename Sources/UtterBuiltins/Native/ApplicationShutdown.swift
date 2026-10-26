import Foundation
import UtterContracts
import UtterData
import UtterRuntime

/// Ends the plugin runtime within a fixed bound, so a disposal that never returns cannot
/// leave the process alive after AppKit asked it to quit. Always returns normally: the
/// caller replies "terminate" whatever happened here.
@MainActor
package enum ApplicationShutdown {
    package nonisolated static let limit: Duration = .seconds(5)

    package static func run(
        startup: Task<Void, Never>?,
        application: @escaping @MainActor () -> BuiltinApplication?,
        limit: Duration = ApplicationShutdown.limit,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        log: Log = Log(service: SystemDiagnostics())
    ) async {
        let outcome = await BoundedWait.run(limit: limit, sleep: sleep) {
            await startup?.value
            try await application()?.stop()
        }
        switch outcome {
        case .finished:
            break
        case let .failed(error):
            log.error("Shutdown failed: \(describe(error)); pending: \(pending(application()))")
        case .timedOut:
            guard let running = application() else {
                log.error("Shutdown exceeded \(seconds(limit)) before startup finished")
                return
            }
            let disposing = running.runtime.disposingPluginID ?? "none"
            log.error("Shutdown exceeded \(seconds(limit)); disposing: \(disposing); pending: \(pending(running))")
        }
    }

    private static func pending(_ application: BuiltinApplication?) -> String {
        "[" + (application?.runtime.pendingDisposalPluginIDs ?? []).joined(separator: ", ") + "]"
    }

    /// Plugin ids and error type names only; error messages can carry user text.
    private static func describe(_ error: any Error) -> String {
        guard let failure = error as? PluginShutdownFailure else { return String(describing: type(of: error)) }
        return failure.failures.map { "\($0.pluginID) (\(type(of: $0.cause)))" }.joined(separator: ", ")
    }

    private static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        return String(format: "%gs", Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }
}
