import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterIngress
@testable import UtterWhisper
import UtterModels
import UtterRemoteInference
import UtterContracts
import AVFoundation
import Foundation
import WhisperKit
import XCTest
@testable import UtterPresentation

final class StreamingASRIntegrationTests: XCTestCase {
    func testWhisperStreamingSessionEmitsPartialCallbackFromSampleAudio() async throws {
        try requireStreamingIntegration("whisper")

        let modelFolder = try requireWhisperModelFolder()
        let audioURL = sampleAudioURL()
        let collector = PartialCollector()

        let compute = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )
        let whisperKit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: modelFolder.path,
                computeOptions: compute,
                verbose: false,
                prewarm: false,
                load: false
            )
        )
        try await whisperKit.prewarmModels()
        try await whisperKit.loadModels()

        let session = WhisperStreamingSession(
            whisperKit: whisperKit,
            partialHandler: { text in
                Task { await collector.record(text) }
            },
            optionsBuilder: {
                DecodingOptions(
                    language: "zh",
                    usePrefillPrompt: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    suppressBlank: true
                )
            },
            access: LocalModelAccessGate(), log: UtterContracts.Log(service: TestDiagnostics.service)
        )

        let feedTask = Task {
            try await feedAudioFile(audioURL) { buffer in
                session.append(buffer)
            }
        }
        let partials = await waitForPartial(in: collector, timeoutSeconds: 45)
        try await feedTask.value
        _ = await session.finishLivePreview()

        XCTAssertFalse(partials.isEmpty, "Whisper streaming session did not emit a partial callback before finish")
        print("WHISPER_STREAM_PARTIAL_COUNT=\(partials.count)")
        print("WHISPER_STREAM_FIRST_PARTIAL=\(partials[0])")
    }

    func testVolcStreamingSessionEmitsPartialCallbackFromSampleAudio() async throws {
        try requireStreamingIntegration("volc")

        let config = try requireVolcConfig()
        let audioURL = sampleAudioURL()
        let collector = PartialCollector()
        let engine = VolcSpeechEngine(
            appKey: config.appKey,
            accessKey: config.accessKey,
            resourceId: config.resourceId
        )

        engine.startListening(language: "zh") { text in
            Task { await collector.record(text) }
        }

        let feedTask = Task {
            try await feedAudioFile(audioURL) { buffer in
                engine.appendAudioBuffer(buffer)
            }
        }
        let partials = await waitForPartial(in: collector, timeoutSeconds: 45)
        try await feedTask.value
        engine.cancelListening()

        XCTAssertFalse(partials.isEmpty, "Volc streaming session did not emit a partial callback before finish")
        print("VOLC_STREAM_PARTIAL_COUNT=\(partials.count)")
        print("VOLC_STREAM_FIRST_PARTIAL=\(partials[0])")
    }
}

private actor PartialCollector {
    private var partials: [String] = []

    func record(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        partials.append(trimmed)
    }

    func snapshot() -> [String] {
        partials
    }
}

private struct VolcIntegrationConfig {
    let appKey: String
    let accessKey: String
    let resourceId: String
}

private func requireStreamingIntegration(_ engine: String) throws {
    let value = ProcessInfo.processInfo.environment["OPENTYPE_STREAMING_INTEGRATION"] ?? ""
    let requested = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    guard requested.contains("all") || requested.contains(engine) else {
        throw XCTSkip("Set OPENTYPE_STREAMING_INTEGRATION=\(engine) or all to run this integration test")
    }
}

private func requireWhisperModelFolder() throws -> URL {
    let defaults = appDefaults()
    let modelID = ProcessInfo.processInfo.environment["OPENTYPE_WHISPER_MODEL"]
        ?? defaults["whisperModel"] as? String
        ?? "openai_whisper-large-v3_947MB"
    let rootPath = ProcessInfo.processInfo.environment["OPENTYPE_MODEL_STORAGE_PATH"]
        ?? defaults["modelStoragePath"] as? String
        ?? "\(NSHomeDirectory())/Library/Application Support/OpenType/huggingface"
    let folder = URL(fileURLWithPath: rootPath)
        .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        .appendingPathComponent(modelID)

    let required = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
    guard required.allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }) else {
        throw XCTSkip("Whisper model is not downloaded at \(folder.path)")
    }
    return folder
}

private func requireVolcConfig() throws -> VolcIntegrationConfig {
    let defaults = appDefaults()
    guard let appKey = defaults["volcAppKey"] as? String, !appKey.isEmpty else {
        throw XCTSkip("Missing volcAppKey in com.opentype.voiceinput defaults")
    }
    guard let accessKey = defaults["volcAccessKey"] as? String, !accessKey.isEmpty else {
        throw XCTSkip("Missing volcAccessKey in com.opentype.voiceinput defaults")
    }
    let resourceId = (defaults["volcResourceId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        ?? "volc.bigasr.sauc.duration"
    return VolcIntegrationConfig(appKey: appKey, accessKey: accessKey, resourceId: resourceId)
}

private func appDefaults() -> [String: Any] {
    UserDefaults.standard.persistentDomain(forName: "com.opentype.voiceinput") ?? [:]
}

private func sampleAudioURL() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/assets/demos/zh-sample.m4a")
}

private func waitForPartial(in collector: PartialCollector, timeoutSeconds: TimeInterval) async -> [String] {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        let snapshot = await collector.snapshot()
        if !snapshot.isEmpty {
            return snapshot
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
    }
    return await collector.snapshot()
}

private func feedAudioFile(
    _ url: URL,
    frameCount: AVAudioFrameCount = 4096,
    delayNanoseconds: UInt64 = 120_000_000,
    append: (AVAudioPCMBuffer) -> Void
) async throws {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat

    while file.framePosition < file.length {
        try Task.checkCancellation()
        let remainingFrames = AVAudioFrameCount(file.length - file.framePosition)
        let framesToRead = min(frameCount, remainingFrames)
        guard framesToRead > 0 else { break }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer, frameCount: framesToRead)
        guard buffer.frameLength > 0 else { break }

        append(buffer)
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }
}
