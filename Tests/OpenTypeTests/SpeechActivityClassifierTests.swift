import AVFoundation
import XCTest
@testable import OpenType

final class SpeechActivityClassifierTests: XCTestCase {
    func testGeneratedAmbientSoundsAreNotSpeech() async throws {
        for amplitude: Float in [0.007, 0.04, 0.2] {
            for tone in [false, true] {
                let url = try makeAmbientAudio(amplitude: amplitude, tone: tone)
                defer { try? FileManager.default.removeItem(at: url) }
                let hasSpeech = await SpeechActivityClassifier.containsSpeech(at: url)
                XCTAssertFalse(hasSpeech, "amplitude \(amplitude), tone \(tone)")
            }
        }
    }

    func testDetectsRepositorySpeechAndShortClips() async throws {
        for sample in ["en-sample.m4a", "zh-sample.m4a"] {
            let sourceURL = repositorySample(sample)
            let fullSpeech = await SpeechActivityClassifier.containsSpeech(at: sourceURL)
            XCTAssertTrue(fullSpeech, sample)

            for seconds in [0.8, 0.25] {
                for gain: Float in [1, 0.1] {
                    let clipURL = try makeClip(from: sourceURL, seconds: seconds, gain: gain)
                    defer { try? FileManager.default.removeItem(at: clipURL) }
                    let shortSpeech = await SpeechActivityClassifier.containsSpeech(at: clipURL)
                    XCTAssertTrue(shortSpeech, "\(sample), \(seconds)s, gain \(gain)")
                }
            }
        }
    }

    func testMissingEmptyAndCancelledAudioFailClosed() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-missing-\(UUID().uuidString).wav")
        let missingResult = await SpeechActivityClassifier.containsSpeech(at: missing)
        XCTAssertFalse(missingResult)
        let nilResult = await SpeechActivityClassifier.containsSpeech(at: nil)
        XCTAssertFalse(nilResult)

        let emptyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-empty-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: emptyURL) }
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        _ = try AVAudioFile(forWriting: emptyURL, settings: format.settings)
        let emptyResult = await SpeechActivityClassifier.containsSpeech(at: emptyURL)
        XCTAssertFalse(emptyResult)

        let cancelledResult = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await SpeechActivityClassifier.containsSpeech(at: repositorySample("en-sample.m4a"))
        }.value
        XCTAssertFalse(cancelledResult)
    }

    private func repositorySample(_ filename: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/assets/demos/\(filename)")
    }

    private func makeAmbientAudio(amplitude: Float, tone: Bool) throws -> URL {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
        buffer.frameLength = 32_000
        var seed: UInt32 = 1
        for index in 0..<Int(buffer.frameLength) {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let noise = Float(seed) / Float(UInt32.max) - 0.5
            let value = tone ? sin(Float(index) * 2 * .pi * 220 / 16_000) : noise
            buffer.floatChannelData![0][index] = value * amplitude
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-ambient-\(UUID().uuidString).wav")
        let output = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try output.write(from: buffer)
        return url
    }

    private func makeClip(from sourceURL: URL, seconds: Double, gain: Float) throws -> URL {
        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        source.framePosition = AVAudioFramePosition(format.sampleRate)
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        try source.read(into: buffer, frameCount: frames)
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                buffer.floatChannelData![channel][frame] *= gain
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-short-speech-\(UUID().uuidString).wav")
        let output = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try output.write(from: buffer)
        return url
    }
}
