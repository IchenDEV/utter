import Foundation

package struct AudioCaptureActivity: Equatable, Sendable {
    package let thresholds: AudioActivityThresholds

    package private(set) var bufferCount = 0
    package private(set) var frameCount = 0
    package private(set) var maxRMS: Float = 0
    private var weightedRMSSum: Double = 0

    package init(thresholds: AudioActivityThresholds = .default) {
        self.thresholds = thresholds
    }

    package var averageRMS: Float {
        guard frameCount > 0 else { return 0 }
        return Float(weightedRMSSum / Double(frameCount))
    }

    package var hasMeaningfulAudio: Bool {
        guard frameCount > 0 else { return false }
        let gate = thresholds.gate
        return averageRMS >= gate.minimumAverageRMS || maxRMS >= gate.minimumPeakRMS
    }

    package var hasWeakSpeechEvidence: Bool {
        guard frameCount > 0 else { return true }
        let weak = thresholds.weakSpeechEvidence
        return averageRMS < weak.averageRMS && maxRMS < weak.peakRMS
    }

    package mutating func record(rms: Float, frameCount: Int) {
        guard frameCount > 0 else { return }
        let normalizedRMS = max(0, rms)
        bufferCount += 1
        self.frameCount += frameCount
        maxRMS = max(maxRMS, normalizedRMS)
        weightedRMSSum += Double(normalizedRMS) * Double(frameCount)
    }
}
