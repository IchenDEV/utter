import Foundation

package struct DownloadProgressInfo: Equatable, Sendable {
    package let fraction: Double
    package let elapsedSeconds: TimeInterval
    package let completedBytes: Int64
    package let totalBytes: Int64
    package let speedBytesPerSecond: Double

    package init(
        fraction: Double,
        elapsedSeconds: TimeInterval,
        completedBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSecond: Double
    ) {
        let completedBytes = max(completedBytes, 0)
        self.fraction = Self.clampFraction(fraction)
        self.elapsedSeconds = elapsedSeconds.isFinite ? max(elapsedSeconds, 0) : 0
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes > 0 ? max(totalBytes, completedBytes) : 0
        self.speedBytesPerSecond = speedBytesPerSecond.isFinite ? max(speedBytesPerSecond, 0) : 0
    }

    package var percentText: String {
        "\(Int(clampedFraction * 100))%"
    }

    package var elapsedText: String {
        Self.formatDuration(elapsedSeconds)
    }

    package var transferredText: String {
        guard completedBytes > 0 else { return "" }
        guard totalBytes > 0 else { return Self.formatBytes(completedBytes) }
        return "\(Self.formatBytes(completedBytes)) / \(Self.formatBytes(totalBytes))"
    }

    package var remainingText: String {
        guard totalBytes > 0 else { return L("download.unknown") }
        return Self.formatBytes(max(totalBytes - completedBytes, 0))
    }

    package var speedText: String {
        guard speedBytesPerSecond >= 1 else { return L("download.unknown") }
        return "\(Self.formatBytes(Int64(speedBytesPerSecond.rounded())))/s"
    }

    package var detailText: String {
        [
            String(format: L("download.elapsed_format"), elapsedText),
            String(format: L("download.progress_format"), percentText),
            String(format: L("download.remaining_format"), remainingText),
            String(format: L("download.speed_format"), speedText),
        ].joined(separator: " · ")
    }

    private var clampedFraction: Double {
        Self.clampFraction(fraction)
    }

    package static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1e6) }
        if bytes >= 1_000 { return String(format: "%.0f KB", Double(bytes) / 1e3) }
        return "\(bytes) B"
    }

    package static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    package static func clampFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

