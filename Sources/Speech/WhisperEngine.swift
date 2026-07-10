import Foundation
import AVFoundation
import WhisperKit
import CoreML

final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private let modelName: String?
    private(set) var isReady = false
    private(set) var isLoading = false
    private var loadError: String?
    private var streamingSession: WhisperStreamingSession?

    init(modelName: String = "large-v3") {
        self.modelName = modelName.isEmpty ? nil : modelName
    }

    struct DownloadProgress {
        var fraction: Double
        var completedBytes: Int64
        var totalBytes: Int64
        var speedBytesPerSec: Double
        var elapsedSeconds: TimeInterval
        var downloadFraction: Double
        var stage: Stage

        enum Stage: String {
            case downloading = "下载中"
            case compiling = "编译模型"
            case loading = "加载模型"
            case done = "完成"
        }

        var info: DownloadProgressInfo {
            DownloadProgressInfo(
                fraction: downloadFraction,
                elapsedSeconds: elapsedSeconds,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                speedBytesPerSecond: speedBytesPerSec
            )
        }

        var sizeText: String {
            info.transferredText
        }

        var speedText: String {
            info.speedText
        }

        var remainingText: String {
            info.remainingText
        }

        var detailText: String {
            info.detailText
        }
    }

    func loadModel(progress: @escaping (DownloadProgress) -> Void) async throws {
        guard !isLoading && !isReady else { return }
        isLoading = true

        do {
            let recommended = WhisperKit.recommendedModels()
            var selectedModel = modelName ?? recommended.default
            let localFolder = ModelStorage.localWhisperURL(selectedModel)

            if localFolder == nil, !recommended.supported.contains(selectedModel) {
                if let match = recommended.supported.first(where: {
                    $0.localizedCaseInsensitiveContains(selectedModel)
                }) {
                    Log.info("[WhisperEngine] '\(selectedModel)' not in list, matched: \(match)")
                    selectedModel = match
                } else {
                    Log.info("[WhisperEngine] '\(selectedModel)' not in list, fallback: \(recommended.default)")
                    selectedModel = recommended.default
                }
            }
            Log.info("[WhisperEngine] using model: \(selectedModel)")

            progress(dp(0.02, stage: .downloading))

            let modelDir = ModelStorage.whisperVariantDir(selectedModel)
            let tracker = DownloadProgressTracker(initialBytes: ModelStorage.directorySize(at: modelDir))

            let folder: URL
            if let localFolder {
                folder = localFolder
            } else {
                do {
                    folder = try await WhisperKit.download(
                        variant: selectedModel,
                        downloadBase: ModelCatalog.whisperDownloadBase,
                        progressCallback: { p in
                            let downloadedBytes = ModelStorage.directorySize(at: modelDir)
                            let completed = downloadedBytes > 0 ? downloadedBytes : p.completedUnitCount
                            let total = p.totalUnitCount

                            let frac = 0.02 + p.fractionCompleted * 0.58
                            let info = tracker.update(
                                completedBytes: completed,
                                totalBytes: total,
                                fraction: frac
                            )
                            progress(DownloadProgress(
                                fraction: frac, completedBytes: completed,
                                totalBytes: total,
                                speedBytesPerSec: info.speedBytesPerSecond,
                                elapsedSeconds: info.elapsedSeconds,
                                downloadFraction: p.fractionCompleted,
                                stage: .downloading
                            ))
                        }
                    )
                } catch {
                    isLoading = false
                    throw WhisperError.downloadFailed(error.localizedDescription)
                }
            }
            Log.info("[WhisperEngine] download complete")

            progress(dp(0.62, stage: .compiling))

            let compute = ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )

            let kit: WhisperKit
            do {
                kit = try await WhisperKit(
                    WhisperKitConfig(
                        modelFolder: folder.path,
                        computeOptions: compute,
                        verbose: false,
                        prewarm: false,
                        load: false
                    )
                )

                progress(dp(0.70, stage: .compiling))
                try await kit.prewarmModels()
            } catch {
                isLoading = false
                throw WhisperError.compileFailed(error.localizedDescription)
            }

            progress(dp(0.85, stage: .loading))
            do {
                try await kit.loadModels()
            } catch {
                isLoading = false
                throw WhisperError.loadFailed(error.localizedDescription)
            }

            whisperKit = kit
            isReady = true
            isLoading = false
            loadError = nil
            progress(dp(1.0, stage: .done))
            Log.info("[WhisperEngine] model loaded")
        } catch let error as WhisperError {
            loadError = error.localizedDescription
            isReady = false
            Log.error("[WhisperEngine] \(error.localizedDescription)")
            throw error
        } catch {
            loadError = error.localizedDescription
            isReady = false
            isLoading = false
            Log.error("[WhisperEngine] model load failed: \(error.localizedDescription)")
            throw error
        }
    }

    var supportsStreaming: Bool { true }

    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        guard let whisperKit, isReady else { return }
        streamingSession = WhisperStreamingSession(
            whisperKit: whisperKit,
            partialHandler: onPartialResult,
            optionsBuilder: { [weak self] in
                self?.decodingOptions(language: language) ?? DecodingOptions()
            }
        )
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        streamingSession?.append(buffer)
    }

    func finishListening(audioURL: URL?, language: String?) async throws -> String {
        defer { streamingSession = nil }
        if let streamingSession {
            let outcome = await streamingSession.finishLivePreview()
            return try await StreamingTranscriptResolver.resolveFinalTranscript(
                engineName: "WhisperEngine",
                audioURL: audioURL,
                livePreviewText: outcome.livePreviewText,
                metrics: outcome.metrics,
                unitLabel: "samples"
            ) { [weak self] in
                guard let self else { return "" }
                return try await self.transcribe(audioURL: audioURL, language: language)
            }
        }
        return try await transcribe(audioURL: audioURL, language: language)
    }

    func cancelListening() {
        streamingSession?.cancel()
        streamingSession = nil
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let whisperKit, isReady else {
            throw WhisperError.modelNotLoaded(loadError ?? "未知原因")
        }
        guard let url = audioURL else {
            throw WhisperError.noAudioFile
        }

        let t0 = CFAbsoluteTimeGetCurrent()

        let results = try await whisperKit.transcribe(audioPath: url.path, decodeOptions: decodingOptions(language: language))
        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[WhisperEngine] transcribed \(text.count) chars in \(String(format: "%.1f", elapsed))s")
        return text
    }

    func unload() {
        cancelListening()
        whisperKit = nil
        isReady = false
        isLoading = false
        loadError = nil
    }

    private func decodingOptions(language: String?) -> DecodingOptions {
        let promptTokens = chinesePromptTokens(for: language)
        return DecodingOptions(
            language: language,
            temperatureFallbackCount: 1,
            usePrefillPrompt: language != nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: true
        )
    }

    private func chinesePromptTokens(for language: String?) -> [Int]? {
        guard language == "zh" else { return nil }
        return whisperKit?.tokenizer?.encode(text: "以下是普通话的句子。")
    }

    private func dp(_ fraction: Double, stage: DownloadProgress.Stage) -> DownloadProgress {
        DownloadProgress(
            fraction: fraction,
            completedBytes: 0,
            totalBytes: 0,
            speedBytesPerSec: 0,
            elapsedSeconds: 0,
            downloadFraction: fraction,
            stage: stage
        )
    }
}

enum WhisperError: LocalizedError {
    case modelNotLoaded(String)
    case noAudioFile
    case downloadFailed(String)
    case compileFailed(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let detail): return String(format: L("error.whisper_not_loaded"), detail)
        case .noAudioFile: return L("error.no_audio")
        case .downloadFailed(let detail): return String(format: L("error.download_failed"), detail)
        case .compileFailed(let detail): return String(format: L("error.compile_failed"), detail)
        case .loadFailed(let detail): return String(format: L("error.load_failed"), detail)
        }
    }
}
