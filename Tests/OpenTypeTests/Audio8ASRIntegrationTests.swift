import AVFoundation
import Darwin
import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMLX
import UtterModels
import UtterPresentationContracts

@MainActor
final class Audio8ASRIntegrationTests: XCTestCase {
    func testDownloadedModelTranscribesChineseEnglishAndAppliesHotwords() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_AUDIO8_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_AUDIO8_INTEGRATION=1 to run the Audio8 integration test")
        }
        let modelPath = try XCTUnwrap(environment["OPENTYPE_AUDIO8_MODEL_PATH"])
        let engine = Audio8NativeASREngine(modelPath: modelPath)
        XCTAssertTrue(engine.isReady)
        let root = repositoryRoot()

        let prepareStarted = CFAbsoluteTimeGetCurrent()
        await engine.prepare()
        print("AUDIO8_PREPARE_SECONDS=\(formatSeconds(since: prepareStarted))")

        let englishStarted = CFAbsoluteTimeGetCurrent()
        let english = try await engine.transcribe(
            audioURL: root.appendingPathComponent("docs/assets/demos/en-sample.m4a"),
            language: "en"
        )
        print("AUDIO8_EN_SECONDS=\(formatSeconds(since: englishStarted))")
        print("AUDIO8_PEAK_RSS_GB=\(formatGigabytes(peakResidentBytes()))")
        print("AUDIO8_EN_TEXT=\(english)")
        XCTAssertTrue(english.localizedCaseInsensitiveContains("design doc"), english)

        let chineseStarted = CFAbsoluteTimeGetCurrent()
        let chinese = try await engine.transcribe(
            audioURL: root.appendingPathComponent("docs/assets/demos/zh-sample.m4a"),
            language: "zh"
        )
        print("AUDIO8_ZH_SECONDS=\(formatSeconds(since: chineseStarted))")
        print("AUDIO8_ZH_TEXT=\(chinese)")
        XCTAssertTrue(chinese.contains("周五"), chinese)

        engine.configureRecognition(context: SpeechRecognitionContext(phrases: ["Audio8", "AutoArk"]))
        let boosted = try await engine.transcribe(
            audioURL: root.appendingPathComponent("docs/assets/demos/en-sample.m4a"),
            language: "en"
        )
        print("AUDIO8_HOTWORD_TEXT=\(boosted)")
        XCTAssertFalse(boosted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        await engine.shutdown()
    }

    func testLongAudioFailsBeforeInference() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_AUDIO8_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_AUDIO8_INTEGRATION=1 to run the Audio8 integration test")
        }
        let modelPath = try XCTUnwrap(environment["OPENTYPE_AUDIO8_MODEL_PATH"])
        let engine = Audio8NativeASREngine(modelPath: modelPath)
        XCTAssertTrue(engine.isReady)
        let audioURL = try makeSilentWAV(frames: 480_001)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await engine.transcribe(audioURL: audioURL, language: "en")
            XCTFail("Audio8 must reject audio longer than 30 seconds")
        } catch Audio8ASRError.audioTooLong {
            // Expected explicit failure.
        }
    }

    func testDamagedAssetsFailExplicitlyWithoutFallback() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_AUDIO8_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_AUDIO8_INTEGRATION=1 to run the Audio8 integration test")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-audio8-damaged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for file in Audio8ASRModel.requiredFiles where file != "model.safetensors" {
            try Data("{}".utf8).write(to: dir.appendingPathComponent(file))
        }
        let missingEngine = Audio8NativeASREngine(modelPath: dir.path)
        XCTAssertFalse(missingEngine.isReady)
        do {
            _ = try await missingEngine.transcribe(
                audioURL: repositoryRoot().appendingPathComponent("docs/assets/demos/en-sample.m4a"),
                language: "en"
            )
            XCTFail("Missing weights must fail explicitly")
        } catch Audio8ASRError.notConfigured {
            // Expected explicit configuration/readiness failure.
        }

        try Data("corrupt-weights".utf8).write(to: dir.appendingPathComponent("model.safetensors"))
        let corruptEngine = Audio8NativeASREngine(modelPath: dir.path)
        XCTAssertTrue(corruptEngine.isReady)
        do {
            _ = try await corruptEngine.transcribe(
                audioURL: repositoryRoot().appendingPathComponent("docs/assets/demos/en-sample.m4a"),
                language: "en"
            )
            XCTFail("Corrupt assets must fail explicitly")
        } catch is Audio8ASRError {
            // Expected explicit failure.
        }
    }

    func testCancelledTranscriptionPropagatesCancellation() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_AUDIO8_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_AUDIO8_INTEGRATION=1 to run the Audio8 integration test")
        }
        let modelPath = try XCTUnwrap(environment["OPENTYPE_AUDIO8_MODEL_PATH"])
        let engine = Audio8NativeASREngine(modelPath: modelPath)
        await engine.prepare()

        let audioURL = repositoryRoot().appendingPathComponent("docs/assets/demos/en-sample.m4a")
        let task = Task {
            try await engine.transcribe(audioURL: audioURL, language: "en")
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled Audio8 transcription must throw CancellationError")
        } catch is CancellationError {
            // Expected cancellation propagation.
        }
        await engine.shutdown()
    }

    func testInstalledCatalogReloadsOfflineAndDeletesAudio8() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_AUDIO8_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_AUDIO8_INTEGRATION=1 to run the Audio8 integration test")
        }
        let modelPath = try XCTUnwrap(environment["OPENTYPE_AUDIO8_MODEL_PATH"])
        let sourceDir = URL(fileURLWithPath: modelPath)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-audio8-installed-\(UUID().uuidString)")
        let defaultsSuite = "Audio8Installed-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.set(root.path, forKey: "modelStoragePath")
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: root)
        }

        let id = Audio8ASRModel.defaultID
        let repoDir = ModelStorage.asrRepoDir(id, downloadBase: root)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        for file in Audio8ASRModel.requiredFiles {
            try FileManager.default.createSymbolicLink(
                at: repoDir.appendingPathComponent(file),
                withDestinationURL: sourceDir.appendingPathComponent(file)
            )
        }
        try ASRModelRevisionMarker.write(revision: Audio8ASRModel.revision, to: repoDir)

        let settings = AppSettings(service: SettingsStore(defaults: defaults))
        let catalog = ModelCatalog(
            settings: settings,
            log: Log(service: TestDiagnostics.service),
            access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(download: { _, _, _, _ in }, validate: { _ in }),
            artifacts: MLXModelArtifacts.text + MLXModelArtifacts.speech,
            speechDescriptors: { MLXModelArtifacts.speechDescriptors },
            startupStorageRoot: root,
            startupCleanup: { _ in Task { 0 } }
        )
        catalog.refreshASRStatus(recheckingErrors: true)
        let installedIndex = try XCTUnwrap(catalog.asrModels.firstIndex(where: { $0.id == id }))
        XCTAssertEqual(catalog.asrModels[installedIndex].status, .downloaded)
        let installedPath = catalog.asrModelPath(for: id)
        XCTAssertEqual(installedPath, repoDir.standardizedFileURL.path)

        // Simulate app restart with a fresh ModelCatalog reading the persisted storage root.
        let restartedCatalog = ModelCatalog(
            settings: settings,
            log: Log(service: TestDiagnostics.service),
            access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(download: { _, _, _, _ in }, validate: { _ in }),
            artifacts: MLXModelArtifacts.text + MLXModelArtifacts.speech,
            speechDescriptors: { MLXModelArtifacts.speechDescriptors },
            startupStorageRoot: root,
            startupCleanup: { _ in Task { 0 } }
        )
        restartedCatalog.refreshASRStatus(recheckingErrors: true)
        let restartedPath = restartedCatalog.asrModelPath(for: id)
        XCTAssertEqual(restartedPath, installedPath)
        let offlineEngine = Audio8NativeASREngine(modelPath: restartedPath)
        let offlineText = try await offlineEngine.transcribe(
            audioURL: repositoryRoot().appendingPathComponent("docs/assets/demos/zh-sample.m4a"),
            language: "zh"
        )
        print("AUDIO8_INSTALLED_RELOAD_TEXT=\(offlineText)")
        XCTAssertTrue(offlineText.contains("周五"), offlineText)
        await offlineEngine.shutdown()

        await restartedCatalog.deleteASR(id)
        let deletedIndex = try XCTUnwrap(restartedCatalog.asrModels.firstIndex(where: { $0.id == id }))
        XCTAssertEqual(restartedCatalog.asrModels[deletedIndex].status, .notDownloaded)
        XCTAssertEqual(restartedCatalog.asrModels[deletedIndex].cacheSize, 0)
        XCTAssertTrue(restartedCatalog.asrModelPath(for: id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoDir.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sourceDir.appendingPathComponent("model.safetensors").path
        ))
    }

    func testApplicationCatalogDownloadsReloadsOfflineAndDeletesAudio8() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_AUDIO8_LIVE_DOWNLOAD"] == "1" else {
            throw XCTSkip("Set OPENTYPE_AUDIO8_LIVE_DOWNLOAD=1 for the live Audio8 catalog download")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-audio8-catalog-\(UUID().uuidString)")
        let defaultsSuite = "Audio8Catalog-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.set(root.path, forKey: "modelStoragePath")
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: root)
        }

        let settings = AppSettings(service: SettingsStore(defaults: defaults))
        let catalog = ModelCatalog(
            settings: settings,
            log: Log(service: TestDiagnostics.service),
            access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(download: { _, _, _, _ in }, validate: { _ in }),
            artifacts: MLXModelArtifacts.text + MLXModelArtifacts.speech,
            speechDescriptors: { MLXModelArtifacts.speechDescriptors },
            startupStorageRoot: root,
            startupCleanup: { _ in Task { 0 } }
        )
        let id = Audio8ASRModel.defaultID
        guard let index = catalog.asrModels.firstIndex(where: { $0.id == id }) else {
            return XCTFail("Audio8 must appear in the application catalog")
        }
        XCTAssertEqual(catalog.asrModels[index].status, .notDownloaded)

        var lastReportedBucket = -1
        await catalog.downloadASR(id) { info in
            let bucket = Int(info.fraction * 20)
            if bucket != lastReportedBucket {
                lastReportedBucket = bucket
                let line = "[AUDIO8-DOWNLOAD] bucket=\(bucket) fraction=\(info.fraction) "
                    + "bytes=\(info.completedBytes) of \(info.totalBytes) speed=\(info.speedBytesPerSecond)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
        let downloadedIndex = try XCTUnwrap(catalog.asrModels.firstIndex(where: { $0.id == id }))
        guard catalog.asrModels[downloadedIndex].status == .downloaded else {
            let partial = (try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []
            FileHandle.standardError.write(Data(
                "[AUDIO8-PARTIAL] status=\(catalog.asrModels[downloadedIndex].status) files=\(partial.sorted())\n".utf8
            ))
            return XCTFail("Audio8 download did not complete: \(catalog.asrModels[downloadedIndex].status)")
        }
        let modelPath = catalog.asrModelPath(for: id)
        guard !modelPath.isEmpty else { return XCTFail("Audio8 model path is empty after download") }
        let modelDir = URL(fileURLWithPath: modelPath)
        XCTAssertTrue(ModelCatalog.asrRepoContainsRequiredFiles(id, at: modelDir))

        let downloadedFiles = try FileManager.default.subpathsOfDirectory(atPath: modelPath).sorted()
        print("AUDIO8_DOWNLOADED_FILES=\(downloadedFiles.joined(separator: ","))")
        XCTAssertFalse(downloadedFiles.contains { $0.hasSuffix(".mp4") || $0.hasSuffix(".py") })
        XCTAssertFalse(downloadedFiles.contains {
            $0.hasPrefix("assets/") || $0.hasPrefix("examples/") || $0.hasPrefix("hotword/")
        })

        // Simulate app restart with a fresh ModelCatalog reading the persisted storage root.
        let restartedCatalog = ModelCatalog(
            settings: settings,
            log: Log(service: TestDiagnostics.service),
            access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(download: { _, _, _, _ in }, validate: { _ in }),
            artifacts: MLXModelArtifacts.text + MLXModelArtifacts.speech,
            speechDescriptors: { MLXModelArtifacts.speechDescriptors },
            startupStorageRoot: root,
            startupCleanup: { _ in Task { 0 } }
        )
        restartedCatalog.refreshASRStatus(recheckingErrors: true)
        let restartedPath = restartedCatalog.asrModelPath(for: id)
        XCTAssertEqual(restartedPath, modelPath)
        let offlineEngine = Audio8NativeASREngine(modelPath: restartedPath)
        let offlineText = try await offlineEngine.transcribe(
            audioURL: repositoryRoot().appendingPathComponent("docs/assets/demos/en-sample.m4a"),
            language: "en"
        )
        print("AUDIO8_OFFLINE_RELOAD_TEXT=\(offlineText)")
        XCTAssertTrue(offlineText.localizedCaseInsensitiveContains("design doc"), offlineText)
        await offlineEngine.shutdown()

        await restartedCatalog.deleteASR(id)
        let deletedIndex = try XCTUnwrap(restartedCatalog.asrModels.firstIndex(where: { $0.id == id }))
        XCTAssertEqual(restartedCatalog.asrModels[deletedIndex].status, .notDownloaded)
        XCTAssertEqual(restartedCatalog.asrModels[deletedIndex].cacheSize, 0)
        XCTAssertTrue(restartedCatalog.asrModelPath(for: id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelPath))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeSilentWAV(frames: AVAudioFrameCount) throws -> URL {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        memset(buffer.floatChannelData![0], 0, Int(frames) * MemoryLayout<Float>.size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-audio8-long-\(UUID().uuidString).wav")
        let output = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try output.write(from: buffer)
        return url
    }

    private func formatSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.3f", CFAbsoluteTimeGetCurrent() - start)
    }

    private func peakResidentBytes() -> Int64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int64(usage.ru_maxrss)
    }

    private func formatGigabytes(_ bytes: Int64) -> String {
        String(format: "%.2f", Double(bytes) / 1_073_741_824)
    }
}
