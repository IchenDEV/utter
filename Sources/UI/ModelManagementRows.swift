import SwiftUI

extension ModelManagementView {
    enum ModelType: Equatable {
        case whisper
        case llm
        case asr
    }

    func modelList(
        _ models: [ModelCatalog.ModelEntry], activeID: String, type: ModelType
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                modelRow(model, isActive: model.id == activeID, type: type)
                if index < models.count - 1 { Divider().padding(.horizontal, 10) }
            }
        }
    }

    func modelRow(
        _ model: ModelCatalog.ModelEntry, isActive: Bool, type: ModelType
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                statusDot(model.status)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        if model.tier == .recommended {
                            Text(L("common.recommended"))
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                        if isActive {
                            Text(L("model.active"))
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        compatibilityBadge(model.compatibility)
                    }
                    HStack(spacing: 6) {
                        Text(secondaryText(for: model))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let tps = model.benchmarkTPS {
                            Text(String(format: "%.1f tok/s", tps))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.12))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                if !model.status.isBusy && model.cacheSize > 0 {
                    Text(ModelCatalog.formatBytes(model.cacheSize))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                rowActions(model, isActive: isActive, type: type)
            }

            if model.status.isBusy {
                busyModelStatus(model)
                    .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentColor.opacity(0.04) : .clear)
    }

    @ViewBuilder
    func compatibilityBadge(_ compat: DeviceCapability.Compatibility) -> some View {
        switch compat {
        case .compatible:
            EmptyView()
        case .marginal(let msg):
            Text(L("device.badge_marginal"))
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
                .help(msg)
        case .incompatible(let msg):
            Text(L("device.badge_incompatible"))
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
                .help(msg)
        }
    }

    @ViewBuilder
    func busyModelStatus(_ model: ModelCatalog.ModelEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.status.isDownloading {
                ProgressView(value: model.downloadProgress)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            if !model.downloadDetail.isEmpty {
                Text(model.downloadDetail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func rowActions(
        _ model: ModelCatalog.ModelEntry, isActive: Bool, type: ModelType
    ) -> some View {
        if model.status.isDownloading {
            Button(L("common.cancel")) {
                catalog.cancelDownload(model.id, kind: type.downloadKind)
            }
            .controlSize(.mini)
        } else if canDownload(model, type: type) &&
                    (model.status == .notDownloaded || model.status.isError) {
            Button(model.status.isError ? L("model.resume") : L("common.download")) {
                requestDownload(model, type: type, isActive: isActive)
            }
            .controlSize(.mini)
        }

        if !isActive && (model.status == .downloaded || model.status == .ready) {
            Button(L("model.use")) {
                select(model, type: type)
            }
            .controlSize(.mini)
        }

        if type == .llm && (model.status == .downloaded || model.status == .ready) {
            benchmarkButton(model)
        }

        if model.status.canDelete && model.cacheSize > 0 {
            Button {
                requestDelete(model, type: type, isActive: isActive)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func benchmarkButton(_ model: ModelCatalog.ModelEntry) -> some View {
        if model.isBenchmarking {
            ProgressView()
                .controlSize(.mini)
        } else {
            Button {
                Task { await runBenchmark(model.id) }
            } label: {
                Image(systemName: "speedometer")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("model.benchmark"))
        }
    }

    func download(_ model: ModelCatalog.ModelEntry, type: ModelType) async {
        switch type {
        case .whisper:
            await catalog.downloadWhisper(model.id)
        case .llm:
            await catalog.downloadLLM(model.id)
        case .asr:
            await catalog.downloadASR(model.id)
        }
    }

    func canDownload(_ model: ModelCatalog.ModelEntry, type: ModelType) -> Bool {
        switch type {
        case .whisper:
            return ModelStorage.localWhisperURL(model.id) == nil
        case .llm:
            return ModelStorage.localLLMURL(model.id) == nil
        case .asr:
            return true
        }
    }

    func select(_ model: ModelCatalog.ModelEntry, type: ModelType) {
        switch type {
        case .whisper:
            onUnloadWhisper?()
            settings.whisperModel = model.id
        case .llm:
            onUnloadLLM?()
            settings.useRemoteLLM = false
            settings.llmModel = model.id
            selectedModelFamily = model.family
            onLoadLLM?()
        case .asr:
            onUnloadLocalASR?()
            settings.qwenASRModel = model.id
            settings.speechEngine = .qwen3
        }
    }

    func delete(_ model: ModelCatalog.ModelEntry, isActive: Bool, type: ModelType) {
        if isActive {
            switch type {
            case .whisper:
                onUnloadWhisper?()
            case .llm:
                onUnloadLLM?()
            case .asr:
                onUnloadLocalASR?()
            }
        }

        switch type {
        case .whisper:
            catalog.deleteWhisper(model.id)
        case .llm:
            catalog.deleteLLM(model.id)
        case .asr:
            catalog.deleteASR(model.id)
        }
    }

    func runBenchmark(_ modelID: String) async {
        guard let idx = catalog.llmModels.firstIndex(where: { $0.id == modelID }) else { return }
        catalog.llmModels[idx].isBenchmarking = true
        catalog.llmModels[idx].benchmarkTPS = nil

        do {
            let result = try await benchmarkEngine.benchmark(modelID: modelID)
            if let i = catalog.llmModels.firstIndex(where: { $0.id == modelID }) {
                catalog.llmModels[i].benchmarkTPS = result.tokensPerSecond
                catalog.llmModels[i].isBenchmarking = false
            }
        } catch {
            Log.error("[Benchmark] failed: \(error.localizedDescription)")
            if let i = catalog.llmModels.firstIndex(where: { $0.id == modelID }) {
                catalog.llmModels[i].isBenchmarking = false
            }
        }
    }

    func secondaryText(for model: ModelCatalog.ModelEntry) -> String {
        switch model.status {
        case .unavailable(let message), .error(let message):
            return message
        default:
            return model.hint
        }
    }

    func statusDot(_ status: ModelCatalog.ModelStatus) -> some View {
        Group {
            switch status {
            case .notDownloaded:
                Circle().fill(.secondary.opacity(0.3))
            case .downloading, .compiling, .loading:
                ProgressView().controlSize(.mini)
            case .downloaded, .ready:
                Circle().fill(.green)
            case .unavailable:
                Circle().fill(.orange)
            case .error:
                Circle().fill(.red)
            }
        }
        .frame(width: 8, height: 8)
    }
}
