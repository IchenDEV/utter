import XCTest
@testable import OpenType
import WhisperKit
import Hub
import HuggingFace
import Tokenizers

final class LiveDownloadVerificationTests: XCTestCase {
    func testWhisperKitLiveDownloadInterruptionAndResume() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_LIVE_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1 to run this live download test")
        }

        let variant = "openai_whisper-tiny"
        let token1 = UUID()
        let staging1 = ModelStorage.generationStaging(for: token1)
        try ModelStorage.prepareGeneration(staging1)
        defer { ModelStorage.removeGenerationStaging(staging1) }

        let downloadTask1 = Task { () -> URL in
            let dir = try await WhisperKit.download(
                variant: variant,
                downloadBase: staging1.downloadBase,
                progressCallback: { _ in }
            )
            try Task.checkCancellation()
            return dir
        }

        // Interrupt / Cancel the download
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        downloadTask1.cancel()

        var caughtCancellation = false
        do {
            _ = try await downloadTask1.value
        } catch {
            caughtCancellation = true
            print("[LiveTest-Whisper] Task 1 caught expected interruption: \(error)")
        }
        XCTAssertTrue(caughtCancellation, "Expected download task to be interrupted")

        // Verify staging 1 directory was preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging1.root.path), "Staging 1 directory must be preserved")

        // Now Resume with Generation 2
        let token2 = UUID()
        let staging2 = ModelStorage.generationStaging(for: token2)
        try ModelStorage.prepareGeneration(staging2)
        defer { ModelStorage.removeGenerationStaging(staging2) }

        print("[LiveTest-Whisper] Starting Generation 2 (Resume)...")
        let modelDir2 = try await WhisperKit.download(
            variant: variant,
            downloadBase: staging2.downloadBase,
            progressCallback: { progress in
                if Int(progress.fractionCompleted * 100) % 25 == 0 {
                    print("[LiveTest-Whisper] Gen2 progress: \(Int(progress.fractionCompleted * 100))%")
                }
            }
        )
        print("[LiveTest-Whisper] Gen2 download complete at \(modelDir2.path)")
        XCTAssertTrue(ModelStorage.whisperModelIsComplete(at: modelDir2))

        // Commit generation 2 to published storage
        let targetDir = ModelStorage.whisperVariantDir(variant)
        try? FileManager.default.removeItem(at: targetDir)
        try ModelStorage.commitGeneration(
            kind: .whisper,
            modelID: variant,
            staging: staging2
        )
        print("[LiveTest-Whisper] Generation 2 committed to \(targetDir.path)")
        XCTAssertTrue(ModelStorage.whisperModelIsComplete(at: targetDir))

        // Load model and verify WhisperKit initializes
        print("[LiveTest-Whisper] Loading WhisperKit with published model...")
        let whisperKit = try await WhisperKit(
            modelFolder: targetDir.path,
            verbose: false,
            logLevel: .none
        )
        XCTAssertNotNil(whisperKit.modelState)
        print("[LiveTest-Whisper] WhisperKit successfully loaded with state: \(whisperKit.modelState)")
    }

    func testHubApiLiveDownloadInterruptionAndResume() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_LIVE_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1 to run this live download test")
        }

        let modelID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
        let token1 = UUID()
        let staging1 = ModelStorage.generationStaging(for: token1)
        try ModelStorage.prepareGeneration(staging1)
        defer { ModelStorage.removeGenerationStaging(staging1) }

        let api1 = HubApi(downloadBase: staging1.downloadBase, cache: staging1.hubCache)
        let downloadTask1 = Task { () -> URL in
            let dir = try await api1.snapshot(from: modelID, matching: ["*.json"])
            try Task.checkCancellation()
            return dir
        }

        // Interrupt / Cancel the download
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        downloadTask1.cancel()

        var caughtCancellation = false
        do {
            _ = try await downloadTask1.value
        } catch {
            caughtCancellation = true
            print("[LiveTest-Hub] Task 1 caught expected interruption: \(error)")
        }
        XCTAssertTrue(caughtCancellation, "Expected download task to be interrupted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging1.root.path), "Staging 1 root must be preserved")

        // Resume with Generation 2
        let token2 = UUID()
        let staging2 = ModelStorage.generationStaging(for: token2)
        try ModelStorage.prepareGeneration(staging2)
        defer { ModelStorage.removeGenerationStaging(staging2) }

        let api2 = HubApi(downloadBase: staging2.downloadBase, cache: staging2.hubCache)
        print("[LiveTest-Hub] Starting Generation 2 (Resume)...")
        let modelDir2 = try await api2.snapshot(
            from: modelID,
            matching: ["*.json"]
        ) { progress in
            if Int(progress.fractionCompleted * 100) % 25 == 0 {
                print("[LiveTest-Hub] Gen2 progress: \(Int(progress.fractionCompleted * 100))%")
            }
        }
        print("[LiveTest-Hub] Gen2 download complete at \(modelDir2.path)")

        // Verify symlinks exist in staging2
        let configPath = modelDir2.appendingPathComponent("config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))

        // Commit generation 2 to published storage
        let targetDir = ModelStorage.hubModelRepoDir(modelID, downloadBase: ModelStorage.huggingFaceBase)
        try? FileManager.default.removeItem(at: targetDir)
        try ModelStorage.commitGeneration(
            kind: .llm,
            modelID: modelID,
            staging: staging2
        )
        print("[LiveTest-Hub] Generation 2 committed to \(targetDir.path)")

        // Verify published files are regular files (not dangling symlinks)
        let publishedConfig = targetDir.appendingPathComponent("config.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: publishedConfig.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeRegular, "Committed Hub file must be materialized as regular file")

        // Verify staging 2 removal does not break reading the published model
        ModelStorage.removeGenerationStaging(staging2)
        let configData = try Data(contentsOf: publishedConfig)
        XCTAssertFalse(configData.isEmpty)

        // Load tokenizer from published folder
        print("[LiveTest-Hub] Loading AutoTokenizer from published directory...")
        let tokenizer = try await AutoTokenizer.from(modelFolder: targetDir)
        let encoded = tokenizer.encode(text: "Hello world")
        XCTAssertFalse(encoded.isEmpty)
        let decoded = tokenizer.decode(tokens: encoded)
        XCTAssertEqual(decoded.trimmingCharacters(in: .whitespacesAndNewlines), "Hello world")
        print("[LiveTest-Hub] AutoTokenizer successfully encoded and decoded: \(decoded)")
    }
}
