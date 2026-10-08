import Foundation

/// Fails a download that stops reporting progress so the model row offers
/// Resume again instead of showing an endless progress bar. A stalled transfer
/// otherwise keeps its status at `.downloading` and hides the retry button.
@MainActor
package final class DownloadStallWatchdog {
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var retiredTasks: [Task<Void, Never>] = []
    private var lastActivity = Date()

    package init(timeout: TimeInterval = 120, pollInterval: TimeInterval = 5) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    package func start(onStall: @escaping @MainActor () -> Void) {
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

    package func noteProgress() {
        lastActivity = Date()
    }

    package func stop() {
        if let pollTask {
            pollTask.cancel()
            retiredTasks.append(pollTask)
        }
        pollTask = nil
    }
    package func close() async {
        stop()
        for task in retiredTasks { await task.value }
        retiredTasks.removeAll()
    }

}

/// Tracks download progress so stall detection reacts to real movement.
///
/// Download libraries can keep firing their progress callback with an unchanged
/// value while a socket is dead. Only a higher byte count or fraction counts as
/// progress, so a frozen callback can no longer keep a dead transfer alive.
@MainActor
package final class DownloadProgressSignal {
    package init() {}
    private var lastBytes: Int64 = -1
    private var lastFraction: Double = -1

    package func advanced(completedBytes: Int64, fraction: Double) -> Bool {
        let moved = completedBytes > lastBytes || fraction > lastFraction + 0.000_1
        lastBytes = max(lastBytes, completedBytes)
        lastFraction = max(lastFraction, fraction)
        return moved
    }
}
