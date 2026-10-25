import Foundation
import XCTest
import MLXAudioSTT
import UtterContracts
import UtterMLX
import UtterModels
import UtterWhisper

@MainActor
final class ModelDownloadSourceLiveTests: XCTestCase {
    func testMirrorWhisperDownloadAndOfflineLoad() async throws {
        try await verify(kind: "whisper", test: #function) { fixture, offline in
            let id = try XCTUnwrap(fixture.catalog.snapshot.whisper.first { WhisperModelSelection.matches($0.id, variant: "tiny") }?.id)
            if !offline {
                await fixture.catalog.downloadWhisper(id)
                try requireDownloaded(fixture.catalog.snapshot.whisper.first { $0.id == id }?.status, id: id)
            } else {
                let engine = WhisperEngine(modelName: id, files: fixture.files, access: LocalModelAccessGate(),
                                           log: Log(service: ModelSourceDiagnostics()))
                try await engine.loadModel { _ in }
                XCTAssertTrue(engine.isReady)
                engine.unload()
            }
        }
    }

    func testMirrorMLXDownloadAndOfflineLoad() async throws {
        try await verify(kind: "mlx", test: #function) { fixture, offline in
            let id = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
            if !offline {
                await fixture.catalog.downloadLLM(id)
                try requireDownloaded(fixture.catalog.snapshot.text.first { $0.id == id }?.status, id: id)
            } else {
                let directory = try XCTUnwrap(fixture.files.installedTextModelURL(id))
                try await MLXModelDownloads.validate(directory)
            }
        }
    }

    func testMirrorASRDownloadAndOfflineLoad() async throws {
        try await verify(kind: "asr", test: #function) { fixture, offline in
            let id = QwenASRModel.confuciusR2T2ID
            if !offline {
                let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSTemporaryDirectory())
                let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                guard free > 6 * 1_024 * 1_024 * 1_024 else { throw XCTSkip("ASR staging and publication require 6 GiB free") }
                var lastPercent = -1
                await fixture.catalog.downloadASR(id) { progress in
                    let percent = Int(progress.fraction * 100) / 10 * 10
                    if percent != lastPercent {
                        lastPercent = percent
                        FileHandle.standardError.write(Data("[Mirror ASR] \(percent)%\n".utf8))
                    }
                }
                try requireDownloaded(fixture.catalog.snapshot.speech.first { $0.id == id }?.status, id: id)
            } else {
                let directory = try XCTUnwrap(fixture.files.installedSpeechModelURL(id))
                let model = try await Qwen3ASRModel.fromModelDirectory(directory)
                withExtendedLifetime(model) {}
            }
        }
    }

    private func requireDownloaded(_ status: CatalogModelStatus?, id: String) throws {
        guard status == .downloaded else {
            throw NSError(domain: "UtterMirrorVerification", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(id): \(String(describing: status))"])
        }
    }

    private func verify(kind: String, test: String,
                        body: (ModelSourceIntegration, Bool) async throws -> Void) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UTTER_SOURCE_LIVE_KIND"] == kind else { throw XCTSkip("Opt-in real mirror download: \(kind)") }
        let offline = environment["UTTER_SOURCE_OFFLINE_ROOT"] != nil
        let root = environment["UTTER_SOURCE_OFFLINE_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("UtterMirror-\(UUID().uuidString)")
        let fixture = try await ModelSourceIntegration.start(root: root)
        fixture.settings.modelDownloadSource = .hfMirror
        FileHandle.standardError.write(Data("[Mirror verification] \(kind) \(offline ? "offline load" : "production catalog download")\n".utf8))
        do {
            try await body(fixture, offline)
            if !offline {
                let child = Process()
                child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
                child.arguments = ["-p", "(version 1)(allow default)(deny network-outbound)", "/usr/bin/xcrun", "xctest", "-XCTest",
                    "OpenTypeTests.ModelDownloadSourceLiveTests/" + test.replacingOccurrences(of: "()", with: ""),
                    Bundle(for: Self.self).bundleURL.path]
                var childEnvironment = environment
                childEnvironment["UTTER_SOURCE_OFFLINE_ROOT"] = root.path
                child.environment = childEnvironment
                child.standardOutput = FileHandle.standardOutput
                child.standardError = FileHandle.standardError
                try child.run()
                for _ in 0..<6_000 where child.isRunning { try await Task.sleep(for: .milliseconds(100)) }
                if child.isRunning { child.terminate(); XCTFail("Offline model load exceeded 10 minutes") }
                child.waitUntilExit()
                XCTAssertEqual(child.terminationStatus, 0, "Network-denied model load must succeed")
            }
            try await fixture.close(remove: !offline)
        } catch {
            try? await fixture.close(remove: !offline)
            throw error
        }
    }
}
