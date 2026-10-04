import Foundation
import WhisperKit
import CoreML
import UtterContracts

extension WhisperEngine {
    package func loadModel(progress: @escaping (SpeechModelProgress) -> Void) async throws {
        try await access.withAccess { try await self.loadLocalModel(progress: progress) }
    }

    func loadLocalModel(progress: @escaping (SpeechModelProgress) -> Void) async throws {
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        guard !isLoading && !isReady else { return }
        isLoading = true

        do {
            let recommended = WhisperKit.recommendedModels()
            let requestedModel = modelName ?? recommended.default
            var selectedModel = files.installedWhisperURL(requestedModel) != nil
                ? requestedModel
                : WhisperModelSelection.resolve(
                    requested: requestedModel,
                    available: recommended.supported,
                    fallback: recommended.default
                )
            let localFolder = files.installedWhisperURL(selectedModel)

            if localFolder == nil, !recommended.supported.contains(selectedModel) {
                log.info("[WhisperEngine] '\(selectedModel)' is unavailable, fallback: \(recommended.default)")
                selectedModel = recommended.default
            }
            log.info("[WhisperEngine] using model: \(selectedModel)")

            let folder = localFolder ?? files.whisperVariantURL(selectedModel)
            guard files.whisperModelIsComplete(at: folder) else {
                isLoading = false
                throw UtterContracts.WhisperError.modelNotLoaded(L("model.download_required"))
            }
            log.info("[WhisperEngine] loading local model assets")
            let tokenizerAssets = try WhisperTokenizerAssets.read(at: folder, expectedModel: selectedModel)
            let tokenizer = try await LocalWhisperTokenizer.load(tokenizerAssets)

            progress(dp(0.62, stage: .compiling))

            let compute = ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )

            let kit: OfflineWhisperKit
            do {
                kit = try await OfflineWhisperKit(
                    WhisperKitConfig(
                        modelFolder: folder.path,
                        computeOptions: compute,
                        verbose: false,
                        prewarm: false,
                        load: false,
                        download: false
                    )
                )
                kit.installedTokenizer = tokenizerAssets
                kit.tokenizer = tokenizer

                progress(dp(0.70, stage: .compiling))
                try await kit.prewarmModels()
            } catch {
                isLoading = false
                throw UtterContracts.WhisperError.compileFailed(error.localizedDescription)
            }

            progress(dp(0.85, stage: .loading))
            do {
                try await kit.loadModels()
            } catch {
                isLoading = false
                throw UtterContracts.WhisperError.loadFailed(error.localizedDescription)
            }

            try Task.checkCancellation()
            guard !closed else { throw ProviderCatalogError.closed }
            whisperKit = kit
            isReady = true
            isLoading = false
            loadError = nil
            progress(dp(1.0, stage: .done))
            log.info("[WhisperEngine] model loaded with \(tokenizerAssets.repository), vocabulary \(tokenizerAssets.vocabularySize)")
        } catch let error as UtterContracts.WhisperError {
            loadError = error.localizedDescription
            isReady = false
            log.error("[WhisperEngine] \(error.localizedDescription)")
            throw error
        } catch {
            loadError = error.localizedDescription
            isReady = false
            isLoading = false
            log.error("[WhisperEngine] model load failed: \(error.localizedDescription)")
            throw error
        }
    }

}
