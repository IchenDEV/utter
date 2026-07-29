import Foundation

extension WhisperEngine {
    struct DownloadProgress {
        var fraction: Double
        var completedBytes: Int64
        var totalBytes: Int64
        var speedBytesPerSec: Double
        var elapsedSeconds: TimeInterval
        var downloadFraction: Double
        var stage: Stage

        enum Stage: String {
            case downloading = "下载中"
            case compiling = "编译模型"
            case loading = "加载模型"
            case done = "完成"
        }

        var info: DownloadProgressInfo {
            DownloadProgressInfo(
                fraction: downloadFraction,
                elapsedSeconds: elapsedSeconds,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                speedBytesPerSecond: speedBytesPerSec
            )
        }

        var sizeText: String { info.transferredText }
        var speedText: String { info.speedText }
        var remainingText: String { info.remainingText }
        var detailText: String { info.detailText }
    }
}
