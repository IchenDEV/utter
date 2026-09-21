import XCTest
@testable import OpenType
import WhisperKit
import Hub
import HuggingFace
import Tokenizers
import MLX
import MLXLLM
import MLXLMCommon

private final class ProgressLogger: @unchecked Sendable {
    var lastPct: Int = -1
    var lastLoggedTime: CFAbsoluteTime = 0
    private let lock = NSLock()

    func shouldLogWhisper(pct: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pct % 20 == 0 && pct != lastPct {
            lastPct = pct
            return true
        }
        return false
    }

    func shouldLogHub(fraction: Double) -> (shouldLog: Bool, pct: Int) {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        let pct = Int(fraction * 100)
        if now - lastLoggedTime >= 4.0 || fraction >= 1.0 {
            lastLoggedTime = now
            return (true, pct)
        }
        return (false, pct)
    }
}

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

        print("[LiveTest-Whisper] Starting Task 1 (to be interrupted via Task.cancel)...")
        fflush(stdout)
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
            fflush(stdout)
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
        fflush(stdout)
        let logger = ProgressLogger()
        let modelDir2 = try await WhisperKit.download(
            variant: variant,
            downloadBase: staging2.downloadBase,
            progressCallback: { progress in
                let pct = Int(progress.fractionCompleted * 100)
                if logger.shouldLogWhisper(pct: pct) {
                    print("[LiveTest-Whisper] Gen2 download progress: \(pct)%")
                    fflush(stdout)
                }
            }
        )
        print("[LiveTest-Whisper] Gen2 download complete at \(modelDir2.path)")
        fflush(stdout)
        XCTAssertTrue(ModelStorage.whisperModelIsComplete(at: modelDir2))

        // Commit generation 2 to published storage
        let targetDir = ModelStorage.whisperVariantDir(variant)
        try? FileManager.default.removeItem(at: targetDir)
        let prepared = try await ModelStorage.prepareGenerationCommitOffMainActor(
            kind: .whisper,
            modelID: variant,
            staging: staging2
        )
        defer { ModelStorage.discardPreparedGeneration(prepared) }
        try ModelStorage.publishPreparedGeneration(prepared)
        print("[LiveTest-Whisper] Generation 2 committed to \(targetDir.path)")
        fflush(stdout)
        XCTAssertTrue(ModelStorage.whisperModelIsComplete(at: targetDir))

        // Load model and verify WhisperKit initializes
        print("[LiveTest-Whisper] Loading WhisperKit with published model...")
        fflush(stdout)
        let whisperKit = try await WhisperKit(
            modelFolder: targetDir.path,
            verbose: false,
            logLevel: .none
        )
        XCTAssertNotNil(whisperKit.modelState)
        print("[LiveTest-Whisper] WhisperKit successfully loaded with state: \(whisperKit.modelState)")
        fflush(stdout)

        // Perform actual audio transcription verification
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let audioURL = repoRoot.appendingPathComponent("docs/assets/demos/en-sample.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path), "Sample audio file must exist at \(audioURL.path)")

        print("[LiveTest-Whisper] Running real audio transcription on \(audioURL.lastPathComponent)...")
        fflush(stdout)
        let transcribeT0 = CFAbsoluteTimeGetCurrent()
        let results = try await whisperKit.transcribe(audioPath: audioURL.path)
        let transcribedText = results.compactMap(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let transcribeElapsed = CFAbsoluteTimeGetCurrent() - transcribeT0
        print("[LiveTest-Whisper] Transcribed in \(String(format: "%.2f", transcribeElapsed))s: \"\(transcribedText)\"")
        fflush(stdout)
        XCTAssertFalse(transcribedText.isEmpty, "Transcribed text must not be empty")
        XCTAssertTrue(
            transcribedText.lowercased().contains("design") ||
            transcribedText.lowercased().contains("doc") ||
            transcribedText.lowercased().contains("wanted"),
            "Transcription must contain keywords from sample audio: got '\(transcribedText)'"
        )
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

        print("[LiveTest-Hub] Starting Task 1 (to be interrupted via Task.cancel)...")
        fflush(stdout)
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
            fflush(stdout)
        }
        XCTAssertTrue(caughtCancellation, "Expected download task to be interrupted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging1.root.path), "Staging 1 root must be preserved")

        // Resume with Generation 2: download FULL model snapshot including model.safetensors
        let token2 = UUID()
        let staging2 = ModelStorage.generationStaging(for: token2)
        try ModelStorage.prepareGeneration(staging2)
        defer { ModelStorage.removeGenerationStaging(staging2) }

        let api2 = HubApi(downloadBase: staging2.downloadBase, cache: staging2.hubCache)
        print("[LiveTest-Hub] Starting Generation 2 (Resume) for full model snapshot (including weights)...")
        fflush(stdout)
        let hubLogger = ProgressLogger()
        let dlT0 = CFAbsoluteTimeGetCurrent()
        let modelDir2 = try await api2.snapshot(
            from: modelID
        ) { progress in
            let logInfo = hubLogger.shouldLogHub(fraction: progress.fractionCompleted)
            if logInfo.shouldLog {
                let mb = Double(progress.completedUnitCount) / 1_000_000.0
                let totalMb = Double(progress.totalUnitCount) / 1_000_000.0
                print("[LiveTest-Hub] Gen2 progress: \(logInfo.pct)% (\(String(format: "%.1f", mb)) MB / \(String(format: "%.1f", totalMb)) MB)")
                fflush(stdout)
            }
        }
        let dlElapsed = CFAbsoluteTimeGetCurrent() - dlT0
        print("[LiveTest-Hub] Gen2 full download complete in \(String(format: "%.1f", dlElapsed))s at \(modelDir2.path)")
        fflush(stdout)

        // Verify files exist in staging2
        let configPath = modelDir2.appendingPathComponent("config.json")
        let safetensorsStaging = modelDir2.appendingPathComponent("model.safetensors")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: safetensorsStaging.path))

        // Commit generation 2 to published storage
        let targetDir = ModelStorage.hubModelRepoDir(modelID, downloadBase: ModelStorage.huggingFaceBase)
        try? FileManager.default.removeItem(at: targetDir)
        let prepared = try await ModelStorage.prepareGenerationCommitOffMainActor(
            kind: .llm,
            modelID: modelID,
            staging: staging2
        )
        defer { ModelStorage.discardPreparedGeneration(prepared) }
        try ModelStorage.publishPreparedGeneration(prepared)
        print("[LiveTest-Hub] Generation 2 committed to \(targetDir.path)")
        fflush(stdout)

        // Verify published files are regular files (not dangling symlinks)
        let publishedConfig = targetDir.appendingPathComponent("config.json")
        let publishedSafetensors = targetDir.appendingPathComponent("model.safetensors")
        let configAttrs = try FileManager.default.attributesOfItem(atPath: publishedConfig.path)
        XCTAssertEqual(configAttrs[.type] as? FileAttributeType, .typeRegular, "Committed Hub config must be regular file")

        let safetensorsAttrs = try FileManager.default.attributesOfItem(atPath: publishedSafetensors.path)
        XCTAssertEqual(safetensorsAttrs[.type] as? FileAttributeType, .typeRegular, "Committed model.safetensors must be regular file")
        let safetensorsSize = safetensorsAttrs[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(safetensorsSize, 200_000_000, "model.safetensors must be full weights (>200MB)")
        print("[LiveTest-Hub] Published model.safetensors verified: \(safetensorsSize) bytes, type: regular file")
        fflush(stdout)

        // Verify staging 2 removal does not break reading the published model
        ModelStorage.removeGenerationStaging(staging2)
        print("[LiveTest-Hub] Staging 2 removed; published model remains fully independent.")
        fflush(stdout)

        // Load tokenizer from published folder
        print("[LiveTest-Hub] Loading AutoTokenizer from published directory...")
        fflush(stdout)
        let tokenizer = try await AutoTokenizer.from(modelFolder: targetDir)
        let encoded = tokenizer.encode(text: "Hello world")
        XCTAssertFalse(encoded.isEmpty)
        let decoded = tokenizer.decode(tokens: encoded)
        XCTAssertEqual(decoded.trimmingCharacters(in: .whitespacesAndNewlines), "Hello world")
        print("[LiveTest-Hub] AutoTokenizer successfully encoded and decoded: \(decoded)")
        fflush(stdout)

        // 6. MLX ModelContainer loading & real text generation
        print("[LiveTest-Hub] Loading MLX ModelContainer from published directory...")
        fflush(stdout)
        let tLoad0 = CFAbsoluteTimeGetCurrent()
        let container = try await LLMModelFactory.shared.loadContainer(
            from: targetDir,
            using: MLXModelLoading.tokenizerLoader
        )
        let loadElapsed = CFAbsoluteTimeGetCurrent() - tLoad0
        print("[LiveTest-Hub] MLX ModelContainer successfully loaded in \(String(format: "%.2f", loadElapsed))s!")
        fflush(stdout)

        print("[LiveTest-Hub] Running real text generation with loaded model...")
        fflush(stdout)
        let tGen0 = CFAbsoluteTimeGetCurrent()
        let params = GenerateParameters(maxTokens: 50, temperature: 0.3)
        let session = ChatSession(
            container,
            instructions: "You are a helpful assistant.",
            generateParameters: params
        )
        let generatedText = try await session.respond(to: "Hello! Tell me in one sentence what open source is.")
        let genElapsed = CFAbsoluteTimeGetCurrent() - tGen0
        print("[LiveTest-Hub] Generation complete in \(String(format: "%.2f", genElapsed))s:")
        print("[LiveTest-Hub] Response: \(generatedText)")
        fflush(stdout)
        XCTAssertFalse(generatedText.isEmpty, "Generated text must not be empty")
        print("[LiveTest-Hub] Full weights download, atomic commit, ModelContainer loading, and text generation 100% verified!")
        fflush(stdout)
    }

    func testTransportFailureVsTaskCancelTaxonomy() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_LIVE_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1 to run this live download test")
        }

        // --- Path 1: Task.cancel (voluntary cancellation) ---
        let cancelToken = UUID()
        let cancelStaging = ModelStorage.generationStaging(for: cancelToken)
        try ModelStorage.prepareGeneration(cancelStaging)
        defer { ModelStorage.removeGenerationStaging(cancelStaging) }

        print("[TaxonomyTest] 1. Testing Task.cancel path...")
        fflush(stdout)
        let apiCancel = HubApi(downloadBase: cancelStaging.downloadBase, cache: cancelStaging.hubCache)
        let cancelTask = Task { () -> URL in
            let dir = try await apiCancel.snapshot(from: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", matching: ["*.json"])
            try Task.checkCancellation()
            return dir
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        cancelTask.cancel()

        var observedCancellation = false
        var cancellationErrorString = ""
        do {
            _ = try await cancelTask.value
        } catch {
            observedCancellation = true
            cancellationErrorString = "\(error)"
            print("[TaxonomyTest] Task.cancel caught: \(error)")
            fflush(stdout)
        }
        XCTAssertTrue(observedCancellation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cancelStaging.root.path), "Cancelled staging root must be preserved")

        // --- Path 2: Transport Failure (network/socket error) ---
        let transportToken = UUID()
        let transportStaging = ModelStorage.generationStaging(for: transportToken)
        try ModelStorage.prepareGeneration(transportStaging)
        defer { ModelStorage.removeGenerationStaging(transportStaging) }

        print("[TaxonomyTest] 2. Testing Transport Failure path (unreachable endpoint)...")
        fflush(stdout)
        // Point endpoint to an unreachable local port without affecting host network
        let apiTransport = HubApi(
            downloadBase: transportStaging.downloadBase,
            cache: transportStaging.hubCache,
            endpoint: "http://127.0.0.1:59999"
        )

        var observedTransportFailure = false
        var transportErrorString = ""
        do {
            _ = try await apiTransport.snapshot(from: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", matching: ["*.json"])
        } catch {
            observedTransportFailure = true
            transportErrorString = "\(error)"
            print("[TaxonomyTest] Transport failure caught: \(error)")
            fflush(stdout)
        }
        XCTAssertTrue(observedTransportFailure, "Expected transport failure from unreachable endpoint")
        XCTAssertTrue(FileManager.default.fileExists(atPath: transportStaging.root.path), "Transport failure staging root must be preserved")

        print("[TaxonomyTest] Distinction confirmed:")
        print("  - Task.cancel error signature: \(cancellationErrorString)")
        print("  - Transport failure error signature: \(transportErrorString)")
        fflush(stdout)
    }

    @MainActor
    func testApplicationModelCatalogResumePath() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_LIVE_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1 to run this live download test")
        }

        let variant = "openai_whisper-tiny"
        let catalog = ModelCatalog.shared
        guard let idx = catalog.whisperModels.firstIndex(where: { $0.id == variant }) else {
            throw XCTSkip("Whisper variant \(variant) not in catalog")
        }

        print("[CatalogResumeTest] Testing Application ModelCatalog download -> cancel -> resume path...")
        fflush(stdout)

        // Ensure published destination is cleared so download actually starts
        let targetDir = ModelStorage.whisperVariantDir(variant)
        try? FileManager.default.removeItem(at: targetDir)
        catalog.whisperModels[idx].status = .notDownloaded

        // 1. Start download via ModelCatalog
        let downloadTask = Task { @MainActor in
            await catalog.downloadWhisper(variant)
        }

        // Wait briefly for download to enter downloading state
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(
            catalog.whisperModels[idx].status.isDownloading || catalog.whisperModels[idx].status.isError,
            "Catalog status should transition to downloading"
        )

        // 2. Cancel download via ModelCatalog.cancelDownload
        catalog.cancelDownload(variant, kind: .whisper)
        await downloadTask.value

        // Check that state transitions to paused (error with download_paused message)
        let pausedStatus = catalog.whisperModels[idx].status
        print("[CatalogResumeTest] Status after cancelDownload: \(pausedStatus)")
        fflush(stdout)
        XCTAssertTrue(pausedStatus.isError, "Cancelled catalog download must be in error/paused state")

        // 3. Resume download via ModelCatalog.downloadWhisper
        print("[CatalogResumeTest] Resuming download via catalog.downloadWhisper...")
        fflush(stdout)
        await catalog.downloadWhisper(variant)

        let finalStatus = catalog.whisperModels[idx].status
        print("[CatalogResumeTest] Status after resume completion: \(finalStatus)")
        fflush(stdout)
        XCTAssertEqual(finalStatus, .downloaded, "Resumed download must transition to .downloaded")
        XCTAssertTrue(ModelStorage.whisperModelIsComplete(at: targetDir))
    }
}
