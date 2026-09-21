import Foundation
import XCTest
@testable import OpenType

final class RemoteMicProtocolTests: XCTestCase {
    func testCapabilityFrameParsesV10StereoCodec() throws {
        let payload = Data([0x0B, 0x01, 0x00, 0x02, 0x03, 0x00, 0x78])
        let capabilities = try XCTUnwrap(RemoteMicCapabilities.parse(payload))
        XCTAssertEqual(capabilities.version, 0x0100)
        XCTAssertEqual(capabilities.frameSize, 120)
        XCTAssertEqual(capabilities.selectedCodec, 0x02)
        XCTAssertEqual(capabilities.sampleRate, 16_000)
        XCTAssertTrue(RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate))
    }

    func testCapabilityFrameRejectsNonCapabilityOpcode() {
        XCTAssertNil(RemoteMicCapabilities.parse(Data([0x00, 0x01, 0x00, 0x02, 0x03, 0x00, 0x78])))
        XCTAssertNil(RemoteMicCapabilities.parse(Data([0x0B, 0x01])))
    }

    func testCapabilityFrameFallsBackTo8kHzCodec() throws {
        let payload = Data([0x0B, 0x01, 0x00, 0x01, 0x03, 0x00, 0x78])
        let capabilities = try XCTUnwrap(RemoteMicCapabilities.parse(payload))
        XCTAssertEqual(capabilities.selectedCodec, 0x01)
        XCTAssertEqual(capabilities.sampleRate, 8_000)
        XCTAssertFalse(RemoteMicProtocol.supportsAudio(sampleRate: capabilities.sampleRate))
    }

    func testControlCommandsFollowTheProtocolVersion() {
        XCTAssertEqual(RemoteMicProtocol.microphoneOpen(version: 0x0100, codec: 0x02), Data([0x0C, 0x00]))
        XCTAssertEqual(RemoteMicProtocol.microphoneOpen(version: 0x0010, codec: 0x02), Data([0x0C, 0x00, 0x02]))
        XCTAssertEqual(RemoteMicProtocol.microphoneClose(version: 0x0100, sessionID: 7), Data([0x0D, 0x07]))
        XCTAssertEqual(RemoteMicProtocol.microphoneClose(version: 0x0010, sessionID: 7), Data([0x0D]))
    }

    func testADPCMDecodesHighNibbleFirst() {
        let decoder = RemoteMicADPCMDecoder()
        XCTAssertEqual(decoder.decode(Data([0x70])), [11, 13])
        XCTAssertEqual(decoder.predictor, 13)
    }

    func testADPCMContinuesPredictorAcrossFramesAndResetsOnSync() {
        let decoder = RemoteMicADPCMDecoder()
        XCTAssertEqual(decoder.decode(Data([0x77])), [11, 41])

        decoder.reset(predictor: 100, stepIndex: 4)
        XCTAssertEqual(decoder.decode(Data([0x00])), [101, 102])
        XCTAssertEqual(decoder.predictor, 102)
    }

    func testADPCMClampsPredictorToInt16Bounds() {
        let decoder = RemoteMicADPCMDecoder()
        decoder.reset(predictor: 32_700, stepIndex: 88)
        let samples = decoder.decode(Data([0xFF, 0xFF, 0xFF]))
        XCTAssertEqual(samples.first, -28_736)
        XCTAssertTrue(samples.contains(-32_768))
        XCTAssertTrue(samples.allSatisfy { $0 >= -32_768 && $0 <= 32_767 })
    }

    func testFrameAccumulatorSplitsExactlySizedFrames() {
        var accumulator = RemoteMicFrameAccumulator()
        var stream = Data(repeating: 1, count: 250)
        let frames = accumulator.append(stream, frameSize: 120)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].count, 120)
        XCTAssertEqual(frames[1].count, 120)
        XCTAssertEqual(accumulator.pending.count, 10)

        accumulator.reset()
        XCTAssertTrue(accumulator.pending.isEmpty)
        stream = Data([0x00])
        XCTAssertTrue(accumulator.append(stream, frameSize: 0).isEmpty)
    }

    func testPCMSmoothingUsesNeighborAverage() {
        let processed = RemoteMicPCM.process([0, 400, 0, 0], gainDB: 0)
        XCTAssertEqual(processed, [0, 200, 100, 0])
    }

    func testPCMGainIsAppliedAndClamped() {
        XCTAssertEqual(RemoteMicPCM.process([0, 200, 100, 0], gainDB: 20), [0, 1_250, 1_000, 0])

        let clamped = RemoteMicPCM.process([30_000, 30_000, 30_000], gainDB: 24)
        XCTAssertTrue(clamped.allSatisfy { $0 <= 32_767 && $0 >= -32_768 })
        XCTAssertTrue(RemoteMicPCM.process([], gainDB: 20).isEmpty)
    }
}
