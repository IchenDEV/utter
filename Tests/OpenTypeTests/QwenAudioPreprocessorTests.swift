import AVFoundation
import XCTest
@testable import OpenType

final class QwenAudioPreprocessorTests: XCTestCase {
    func testPreparedAudioIs16kMonoPCMAndIsRemovedAfterUse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenAudioPreprocessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.wav")
        try writeTone(
            to: sourceURL,
            sampleRate: 48_000,
            channels: 2,
            frequency: 1_000
        )

        let preparedURL = try await QwenAudioPreprocessor.withPreparedAudio(from: sourceURL) { url in
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertNotEqual(url, sourceURL)

            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000, accuracy: 0.1)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatInt16)
            XCTAssertLessThanOrEqual(abs(file.length - 16_000), 2)
            return url
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testPreparedAudioIsRemovedWhenUseFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenAudioPreprocessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.wav")
        try writeTone(
            to: sourceURL,
            sampleRate: 44_100,
            channels: 1,
            frequency: 1_000
        )

        var preparedURL: URL?
        do {
            _ = try await QwenAudioPreprocessor.withPreparedAudio(from: sourceURL) { url -> Bool in
                preparedURL = url
                throw ProbeError.expected
            }
            XCTFail("Expected the operation to fail")
        } catch ProbeError.expected {
        }

        let removedURL = try XCTUnwrap(preparedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))
    }

    func testDownsamplingRejectsAudioAboveThe16kNyquistFrequency() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenAudioPreprocessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passbandURL = directory.appendingPathComponent("passband.wav")
        try writeTone(
            to: passbandURL,
            sampleRate: 48_000,
            channels: 1,
            frequency: 1_000
        )
        let rejectedURL = directory.appendingPathComponent("above-nyquist.wav")
        try writeTone(
            to: rejectedURL,
            sampleRate: 48_000,
            channels: 1,
            frequency: 12_000
        )

        let passbandRMS = try await preparedRMS(from: passbandURL)
        let rejectedRMS = try await preparedRMS(from: rejectedURL)

        XCTAssertGreaterThan(passbandRMS, 0.25)
        XCTAssertLessThan(rejectedRMS, passbandRMS * 0.05)
    }

    private func writeTone(
        to url: URL,
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frequency: Double,
        amplitude: Float = 0.5
    ) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: true
            )
        )
        let frameCount = AVAudioFrameCount(sampleRate)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount

        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let samples = try XCTUnwrap(
            audioBuffers.first?.mData?.assumingMemoryBound(to: Float.self)
        )
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let sample = Float(sin(2 * Double.pi * frequency * time)) * amplitude
            for channel in 0..<Int(channels) {
                samples[frame * Int(channels) + channel] = sample
            }
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )
        try file.write(from: buffer)
    }

    private func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        )
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private func preparedRMS(from sourceURL: URL) async throws -> Double {
        try await QwenAudioPreprocessor.withPreparedAudio(from: sourceURL) { url in
            let samples = try readSamples(from: url)
            let stableSamples = samples.dropFirst(1_024).dropLast(1_024)
            let meanSquare = stableSamples.reduce(0.0) { sum, sample in
                sum + Double(sample * sample)
            } / Double(stableSamples.count)
            return sqrt(meanSquare)
        }
    }

    private enum ProbeError: Error {
        case expected
    }
}
