import UtterContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import AVFoundation
import XCTest
import UtterMediaContracts
import UtterRuntime
import UtterAudio

@MainActor
final class AudioFilePluginTests: XCTestCase {
    func testInspectionKeepsCallerFileAcrossSuccessAndShutdown() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("caller.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32))
        buffer.frameLength = 32
        for frame in 0..<32 { buffer.floatChannelData?[0][frame] = 0 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let bytes = try Data(contentsOf: url)
        let runtime = PluginRuntime(catalog: try PluginCatalog([AudioPlugins.files()]))
        try await runtime.start([PluginSelection("audio.files")])
        let service = try runtime.service(AudioServices.files)
        let metadata = try service.inspect(url)
        XCTAssertEqual(metadata.url, url)
        XCTAssertEqual(metadata.frameCount, 32)
        XCTAssertEqual(metadata.sampleRate, 16_000)
        XCTAssertEqual(metadata.channels, 1)
        try await runtime.stop()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertThrowsError(try service.inspect(url)) { XCTAssertTrue($0 is CancellationError) }
    }

    func testInvalidSourcePreservesCallerBytesAndRejectsDirectoryOrNetworkURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("invalid.wav")
        let bytes = Data("not an audio file".utf8)
        try bytes.write(to: url)
        let runtime = PluginRuntime(catalog: try PluginCatalog([AudioPlugins.files()]))
        try await runtime.start([PluginSelection("audio.files")])
        let service = try runtime.service(AudioServices.files)
        XCTAssertThrowsError(try service.inspect(url)) { XCTAssertEqual($0 as? AudioFileError, .invalidAudio) }
        for source in [directory, directory.appendingPathComponent("missing.wav"), URL(string: "https://example.invalid/file.wav")!] {
            XCTAssertThrowsError(try service.inspect(source)) { XCTAssertEqual($0 as? AudioFileError, .unreadable) }
        }
        try await runtime.stop()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
