import Foundation

package struct SpeechModelProgress: Sendable {
    package var fraction: Double
    package var completedBytes: Int64
    package var totalBytes: Int64
    package var speedBytesPerSec: Double
    package var elapsedSeconds: TimeInterval
    package var downloadFraction: Double
    package var stage: Stage

    package enum Stage: String, Sendable {
        case downloading = "下载中"
        case compiling = "编译模型"
        case loading = "加载模型"
        case done = "完成"
    }

    package init(
        fraction: Double, completedBytes: Int64, totalBytes: Int64,
        speedBytesPerSec: Double, elapsedSeconds: TimeInterval,
        downloadFraction: Double, stage: Stage
    ) {
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.elapsedSeconds = elapsedSeconds
        self.downloadFraction = downloadFraction
        self.stage = stage
    }

    package var info: DownloadProgressInfo {
        DownloadProgressInfo(
            fraction: downloadFraction, elapsedSeconds: elapsedSeconds,
            completedBytes: completedBytes, totalBytes: totalBytes,
            speedBytesPerSecond: speedBytesPerSec
        )
    }

    package var sizeText: String { info.transferredText }
    package var speedText: String { info.speedText }
    package var remainingText: String { info.remainingText }
    package var detailText: String { info.detailText }
}
