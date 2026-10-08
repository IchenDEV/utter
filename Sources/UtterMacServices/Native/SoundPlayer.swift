import Foundation
import AVFoundation
import AppKit
import UtterContracts

@MainActor
package final class SoundPlayer: SoundService {
    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?
    private var useSystemSounds = true
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private let enabled: () -> Bool
    private var soundsLoaded = false
    private var closed = false

    package init(enabled: @escaping () -> Bool) { self.enabled = enabled }

    package func playStart() {
        guard !closed, enabled() else { return }
        if !soundsLoaded {
            loadSounds()
            soundsLoaded = true
        }
        if useSystemSounds {
            playTone(frequencies: [523, 659], duration: 0.16, volume: 0.22)
        } else {
            startPlayer?.currentTime = 0
            startPlayer?.play()
        }
    }

    package func playStop() {
        guard !closed, enabled() else { return }
        if !soundsLoaded {
            loadSounds()
            soundsLoaded = true
        }
        if useSystemSounds {
            playTone(frequencies: [494, 392], duration: 0.14, volume: 0.18)
        } else {
            stopPlayer?.currentTime = 0
            stopPlayer?.play()
        }
    }

    package func close() {
        closed = true
        startPlayer?.stop()
        stopPlayer?.stop()
        playerNode?.stop()
        engine?.stop()
        startPlayer = nil
        stopPlayer = nil
        playerNode = nil
        engine = nil
    }

    private func loadSounds() {
        if let startURL = MacServiceResources.bundle.url(forResource: "start", withExtension: "caf", subdirectory: "Sounds"),
           let data = try? Data(contentsOf: startURL), data.count > 100 {
            startPlayer = try? AVAudioPlayer(contentsOf: startURL)
            startPlayer?.prepareToPlay()
            useSystemSounds = false
        }
        if let stopURL = MacServiceResources.bundle.url(forResource: "stop", withExtension: "caf", subdirectory: "Sounds"),
           let data = try? Data(contentsOf: stopURL), data.count > 100 {
            stopPlayer = try? AVAudioPlayer(contentsOf: stopURL)
            stopPlayer?.prepareToPlay()
            useSystemSounds = false
        }
    }

    private func ensureEngine(format: AVAudioFormat) {
        if let engine, engine.isRunning { return }
        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: format)
        try? eng.start()
        engine = eng
        playerNode = node
    }

    /// Two-note tone with smooth cosine envelope and soft harmonics.
    private func playTone(frequencies: [Double], duration: Double, volume: Float) {
        let sampleRate = 44100.0
        let frameCount = Int(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let samples = buffer.floatChannelData?[0] else { return }
        let noteLen = duration / Double(frequencies.count)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let noteIndex = min(Int(t / noteLen), frequencies.count - 1)
            let freq = frequencies[noteIndex]
            let localT = t - Double(noteIndex) * noteLen

            let phase = localT / noteLen
            let envelope = 0.5 * (1.0 - cos(2.0 * .pi * phase))

            let fundamental = sin(2.0 * .pi * freq * t)
            let harmonic = 0.25 * sin(2.0 * .pi * freq * 2.0 * t)

            samples[i] = Float((fundamental + harmonic) * envelope * Double(volume))
        }

        ensureEngine(format: format)
        guard let node = playerNode else { return }

        if node.isPlaying { node.stop() }
        node.play()
        node.scheduleBuffer(buffer, completionHandler: nil)
    }
}
