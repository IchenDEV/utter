import AppKit
import SwiftUI
import AVFoundation
import Speech
import UtterContracts
import UtterPresentationContracts

extension OnboardingView {
    // MARK: - Model Preparation

    var modelPrepPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("onboarding.model_prep"))
                    .font(.system(size: 20, weight: .bold))
                Text(L("onboarding.model_prep_body"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            if let model = catalog.llmModels.first(where: { $0.id == settings.llmModel }) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .medium))
                    if !model.hint.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(model.hint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if model.status.isBusy {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: model.downloadProgress)
                            .progressViewStyle(.linear)
                        if !model.downloadDetail.isEmpty {
                            Text(model.downloadDetail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(model.status == .downloaded || model.status == .ready
                             ? L("onboarding.model_ready")
                             : L("onboarding.downloading_model"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if model.status.isDownloading {
                            Button(L("common.cancel")) {
                                catalog.cancelDownload(model.id, kind: .llm)
                            }
                            .controlSize(.small)
                        }
                    }
                    if model.status.isDownloading {
                        Text(L("model.download_stalled_help"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                } else if model.status == .downloaded || model.status == .ready {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(L("onboarding.model_ready"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else if case .error(let msg) = model.status {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("onboarding.download_failed"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(msg)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Button(L("common.retry")) {
                        showModelDownloadConfirmation = true
                    }
                    .controlSize(.small)
                } else {
                    Text(L("onboarding.download_notice"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button(onboardingDownloadButtonTitle) {
                        showModelDownloadConfirmation = true
                    }
                    .controlSize(.small)
                }
            }

            Spacer()

            if !canContinueFromModelPrep {
                Button(L("onboarding.skip_download")) {
                    skippedModelDownload = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .onAppear {
            catalog.refreshStatus(recheckingErrors: true)
        }
    }

    var onboardingDownloadButtonTitle: String {
        guard let bytes = catalog.estimatedLLMDownloadBytes(settings.llmModel) else {
            return L("common.download")
        }
        return String(
            format: L("onboarding.download_size"),
            ModelCatalogProjection.formatBytes(bytes)
        )
    }

    var onboardingDownloadConfirmationMessage: String {
        let model = catalog.llmModels.first(where: { $0.id == settings.llmModel })
        let estimate = catalog.estimatedLLMDownloadBytes(settings.llmModel)
        let remaining = estimate.map { max($0 - (model?.cacheSize ?? 0), 0) }
        return String(
            format: L("model.download_confirm_message"),
            model?.displayName ?? settings.llmModel,
            remaining.map(ModelCatalogProjection.formatBytes) ?? L("download.unknown"),
            storage.root.path
        )
    }

    var canContinueFromModelPrep: Bool {
        skippedModelDownload ||
        catalog.llmModels.first(where: { $0.id == settings.llmModel })?.status == .downloaded ||
        catalog.llmModels.first(where: { $0.id == settings.llmModel })?.status == .ready
    }

    // MARK: - Ready


}
