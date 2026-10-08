import Foundation

enum AudioTailDrain {
    static func duration(frameCount: Int, sampleRate: Double) -> Duration {
        guard frameCount > 0, sampleRate.isFinite, sampleRate > 0 else { return .zero }
        // Allow the last observed tap quantum to arrive before removing the tap.
        return .seconds(min(0.3, max(0.04, Double(frameCount) / sampleRate + 0.02)))
    }
}
