import Foundation
import UtterContracts

final class DownloadProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let startDate: Date
    private var lastTime: Date
    private var lastBytes: Int64
    private var lastSpeedBytesPerSecond: Double = 0

    init(startDate: Date = Date(), initialBytes: Int64 = 0) {
        self.startDate = startDate
        lastTime = startDate
        lastBytes = max(initialBytes, 0)
    }

    func update(progress: Progress, fraction: Double? = nil) -> DownloadProgressInfo {
        update(
            completedBytes: progress.completedUnitCount,
            totalBytes: progress.totalUnitCount,
            fraction: fraction ?? progress.fractionCompleted
        )
    }

    func update(completedBytes rawCompleted: Int64, totalBytes rawTotal: Int64, fraction: Double? = nil) -> DownloadProgressInfo {
        update(completedBytes: rawCompleted, totalBytes: rawTotal, fraction: fraction, at: Date())
    }

    func update(
        completedBytes rawCompleted: Int64,
        totalBytes rawTotal: Int64,
        fraction: Double? = nil,
        at now: Date
    ) -> DownloadProgressInfo {
        lock.lock()
        defer { lock.unlock() }

        let completedBytes = max(rawCompleted, 0)
        let totalBytes = rawTotal > 0 ? max(rawTotal, completedBytes) : 0
        let sampleElapsed = now.timeIntervalSince(lastTime)
        if sampleElapsed > 0.5 {
            let deltaBytes = completedBytes - lastBytes
            if deltaBytes >= 0 {
                lastSpeedBytesPerSecond = Double(deltaBytes) / sampleElapsed
            } else {
                lastSpeedBytesPerSecond = 0
            }
            lastTime = now
            lastBytes = completedBytes
        }

        let resolvedFraction: Double
        if let fraction {
            resolvedFraction = fraction
        } else if totalBytes > 0 {
            resolvedFraction = Double(completedBytes) / Double(totalBytes)
        } else {
            resolvedFraction = 0
        }

        return DownloadProgressInfo(
            fraction: resolvedFraction,
            elapsedSeconds: now.timeIntervalSince(startDate),
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            speedBytesPerSecond: lastSpeedBytesPerSecond
        )
    }
}
