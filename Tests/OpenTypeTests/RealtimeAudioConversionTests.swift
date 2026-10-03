import UtterMediaContracts
import AVFoundation
import XCTest
@testable import OpenType

final class RealtimeAudioConversionTests: XCTestCase {
    func testStreamingNormalizerConvertsEveryChunk() throws {
        let sampleRate = 44_100.0
        let frameCount = 4_410
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let normalizer = try XCTUnwrap(StreamingAudioNormalizer(inputFormat: format))

        let chunks = [
            try makeBuffer(format: format, frameCount: frameCount, phaseOffset: 0),
            try makeBuffer(format: format, frameCount: frameCount, phaseOffset: frameCount),
            try makeBuffer(format: format, frameCount: frameCount, phaseOffset: frameCount * 2),
        ]

        let converted = try chunks.map { try normalizer.convert($0) }
        let counts = converted.map(\.sampleCount)

        XCTAssertGreaterThan(counts[0], 1_400)
        XCTAssertGreaterThan(counts[1], 1_400)
        XCTAssertGreaterThan(counts[2], 1_400)
        XCTAssertGreaterThan(counts.reduce(0, +), 4_500)
    }

    private func makeBuffer(
        format: AVAudioFormat,
        frameCount: Int,
        phaseOffset: Int
    ) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let frequency = 440.0
        let amplitude: Float = 0.25
        let sampleRate = format.sampleRate

        guard let channel = buffer.floatChannelData?[0] else {
            XCTFail("Missing float channel data")
            return buffer
        }

        for index in 0..<frameCount {
            let t = Double(index + phaseOffset) / sampleRate
            channel[index] = Float(sin(2 * Double.pi * frequency * t)) * amplitude
        }

        return buffer
    }
}
