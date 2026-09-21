import Foundation

/// Fails a download that stops reporting progress so the model row offers
/// Resume again instead of showing an endless progress bar. A stalled transfer
/// otherwise keeps its status at `.downloading` and hides the retry button.
@MainActor
final class DownloadStallWatchdog {
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var lastActivity = Date()

    init(timeout: TimeInterval = 120, pollInterval: TimeInterval = 5) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    func start(onStall: @escaping @MainActor () -> Void) {
        stop()
        lastActivity = Date()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                guard Date().timeIntervalSince(self.lastActivity) >= self.timeout else { continue }
                self.pollTask = nil
                onStall()
                return
            }
        }
    }

    func noteProgress() {
        lastActivity = Date()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}
