import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import UtterContracts
import UtterMediaContracts

extension AudioCaptureManager {
    // MARK: - Capture tap and file writing

    func installCaptureTap() -> Bool {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log.error("[AudioCapture] invalid input format: \(format)")
            return false
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recordingLock.lock()
            defer { self.recordingLock.unlock() }
            guard self.audioFile != nil else { return }
            self.write(buffer)
            self.lastBufferFrameCount = max(self.lastBufferFrameCount, Int(buffer.frameLength))

            let rms = Self.calculateRMS(buffer: buffer)
            self.localLastActivity.record(rms: rms, frameCount: Int(buffer.frameLength))
            self.levelCallback?(Self.visualLevel(fromRMS: rms))

            if let bufferCallback = self.bufferCallback {
                if let copiedBuffer = buffer.copied() {
                    bufferCallback(copiedBuffer)
                } else {
                    log.error("[AudioCapture] unsupported format \(buffer.format.commonFormat.rawValue); dropping streaming buffer")
                }
            }
        }
        return true
    }

    /// Writes a buffer to the recording file, converting when a fallback device
    /// produced a different sample rate or channel layout.
    func write(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile, let target = recordingFormat else { return }
        if buffer.format == target {
            try? audioFile.write(from: buffer)
            return
        }
        guard let converted = convert(buffer, to: target) else { return }
        try? audioFile.write(from: converted)
    }

    func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converterSourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterSourceFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            log.error("[AudioCapture] format conversion failed: \(error.localizedDescription)")
            return nil
        }
        return output
    }

    static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0

        if let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for i in 0..<count { sum += data[i] * data[i] }
            }
            return sqrt(sum / Float(max(count * channelCount, 1)))
        }

        if let channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for i in 0..<count {
                    let sample = Float(data[i]) / Float(Int16.max)
                    sum += sample * sample
                }
            }
            return sqrt(sum / Float(max(count * channelCount, 1)))
        }

        return 0
    }

    static func visualLevel(fromRMS rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = (db + 50) / 50   // map -50dB..0dB → 0..1
        return max(min(normalized, 1.0), 0.0)
    }

}
