import SwiftUI

extension ModelManagementView {
    struct PendingModelAction: Identifiable {
        enum Kind {
            case download
            case delete
        }

        let id = UUID()
        let kind: Kind
        let model: ModelCatalog.ModelEntry
        let type: ModelType
        let isActive: Bool
    }

    struct ActiveModelDownload: Identifiable {
        let model: ModelCatalog.ModelEntry
        let type: ModelType

        var id: String {
            "\(type.downloadKind)-\(model.id)"
        }
    }

    var activeDownloads: [ActiveModelDownload] {
        catalog.whisperModels
            .filter(\.status.isDownloading)
            .map { ActiveModelDownload(model: $0, type: .whisper) } +
        catalog.llmModels
            .filter(\.status.isDownloading)
            .map { ActiveModelDownload(model: $0, type: .llm) } +
        catalog.asrModels
            .filter(\.status.isDownloading)
            .map { ActiveModelDownload(model: $0, type: .asr) }
    }

    var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    var knownStorageBytes: Int64 {
        catalog.whisperModels
            .filter { ModelStorage.localWhisperURL($0.id) == nil }
            .reduce(0) { $0 + $1.cacheSize } +
            catalog.llmModels
            .filter { ModelStorage.localLLMURL($0.id) == nil }
            .reduce(0) { $0 + $1.cacheSize } +
            catalog.asrModels.reduce(0) { $0 + $1.cacheSize }
    }

    var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(format: L("model.downloads_active"), activeDownloads.count),
                systemImage: "arrow.down.circle.fill"
            )
            .font(.headline)

            ForEach(activeDownloads) { download in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(download.model.displayName)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(Int(download.model.downloadProgress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                        Button(L("common.cancel")) {
                            catalog.cancelDownload(
                                download.model.id,
                                kind: download.type.downloadKind
                            )
                        }
                        .controlSize(.mini)
                    }
                    ProgressView(value: download.model.downloadProgress)
                        .progressViewStyle(.linear)
                    if !download.model.downloadDetail.isEmpty {
                        Text(download.model.downloadDetail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(L("model.download_stalled_help"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    func requestDownload(
        _ model: ModelCatalog.ModelEntry,
        type: ModelType,
        isActive: Bool
    ) {
        pendingModelAction = PendingModelAction(
            kind: .download,
            model: model,
            type: type,
            isActive: isActive
        )
    }

    func requestDelete(
        _ model: ModelCatalog.ModelEntry,
        type: ModelType,
        isActive: Bool
    ) {
        pendingModelAction = PendingModelAction(
            kind: .delete,
            model: model,
            type: type,
            isActive: isActive
        )
    }

    func modelActionAlert(_ action: PendingModelAction) -> Alert {
        switch action.kind {
        case .download:
            return Alert(
                title: Text(L("model.download_confirm_title")),
                message: Text(downloadConfirmationMessage(action)),
                primaryButton: .default(Text(L("common.download"))) {
                    Task { await download(action.model, type: action.type) }
                },
                secondaryButton: .cancel()
            )
        case .delete:
            if isImportedLocal(action.model, type: action.type) {
                return Alert(
                    title: Text(L("model.remove_reference_confirm_title")),
                    message: Text(String(
                        format: L("model.remove_reference_confirm_message"),
                        action.model.displayName
                    )),
                    primaryButton: .destructive(Text(L("common.delete"))) {
                        delete(action.model, isActive: action.isActive, type: action.type)
                    },
                    secondaryButton: .cancel()
                )
            }
            return Alert(
                title: Text(L("model.delete_confirm_title")),
                message: Text(String(
                    format: L("model.delete_confirm_message"),
                    action.model.displayName,
                    ModelCatalog.formatBytes(action.model.cacheSize)
                )),
                primaryButton: .destructive(Text(L("common.delete"))) {
                    delete(action.model, isActive: action.isActive, type: action.type)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func downloadConfirmationMessage(_ action: PendingModelAction) -> String {
        let estimate = estimatedDownloadBytes(for: action.model, type: action.type)
        let remaining = estimate.map { max($0 - action.model.cacheSize, 0) }
        let sizeText = remaining.map(ModelCatalog.formatBytes) ?? L("download.unknown")
        var message = String(
            format: L("model.download_confirm_message"),
            action.model.displayName,
            sizeText,
            ModelStorage.root.path
        )
        if let warning = action.model.compatibility.message {
            message += "\n\n⚠️ " + warning
        }
        return message
    }

    private func estimatedDownloadBytes(
        for model: ModelCatalog.ModelEntry,
        type: ModelType
    ) -> Int64? {
        switch type {
        case .whisper:
            return ModelCatalog.estimatedDownloadBytes(from: model.id)
        case .llm:
            return catalog.estimatedLLMDownloadBytes(model.id)
        case .asr:
            return catalog.estimatedASRDownloadBytes(model.id)
        }
    }

    private func isImportedLocal(
        _ model: ModelCatalog.ModelEntry,
        type: ModelType
    ) -> Bool {
        switch type {
        case .whisper:
            return ModelStorage.localWhisperURL(model.id) != nil
        case .llm:
            return ModelStorage.localLLMURL(model.id) != nil
        case .asr:
            return false
        }
    }
}

extension ModelManagementView.ModelType {
    var downloadKind: ModelDownloadKind {
        switch self {
        case .whisper: return .whisper
        case .llm: return .llm
        case .asr: return .asr
        }
    }
}
