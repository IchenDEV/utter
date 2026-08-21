import SwiftUI

extension OnboardingView {
    @ViewBuilder
    var modelPrepPage: some View {
        if ProductEdition.current.capabilities.modelDownloads {
            downloadableModelPrepPage
        } else {
            offlineModelPrepPage
        }
    }

    var offlineModelPrepPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("onboarding.offline_models"))
                    .font(.system(size: 20, weight: .bold))
                Text(L("onboarding.offline_models_body"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            OfflineEditionSummaryView()
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Label(ProductEdition.current.speechModel.displayName, systemImage: "waveform")
                Label(
                    String(
                        format: L("edition.qwen_text_roles"),
                        ProductEdition.current.formattingModel.displayName
                    ),
                    systemImage: "character.bubble"
                )
                Label(L("industry.lexicon.title"), systemImage: "cross.case")
            }
            .font(.system(size: 12))

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    var downloadableModelPrepPage: some View {
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
                modelDownloadContent(model)
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
        .onAppear { catalog.refreshStatus(recheckingErrors: true) }
    }

    @ViewBuilder
    private func modelDownloadContent(_ model: ModelCatalog.ModelEntry) -> some View {
        HStack(spacing: 8) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .medium))
            if !model.hint.isEmpty {
                Text("·").foregroundStyle(.secondary)
                Text(model.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)

        if model.status.isBusy {
            modelDownloadProgress(model)
        } else if model.status == .downloaded || model.status == .ready {
            Label(L("onboarding.model_ready"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        } else if case .error(let message) = model.status {
            modelDownloadError(message)
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

    private func modelDownloadProgress(_ model: ModelCatalog.ModelEntry) -> some View {
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
                Text(L("model.download_stalled_help"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func modelDownloadError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("onboarding.download_failed"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button(L("common.retry")) {
                showModelDownloadConfirmation = true
            }
            .controlSize(.small)
        }
    }

    var onboardingDownloadButtonTitle: String {
        guard let bytes = catalog.estimatedLLMDownloadBytes(settings.llmModel) else {
            return L("common.download")
        }
        return String(format: L("onboarding.download_size"), ModelCatalog.formatBytes(bytes))
    }

    var onboardingDownloadConfirmationMessage: String {
        let model = catalog.llmModels.first(where: { $0.id == settings.llmModel })
        let estimate = catalog.estimatedLLMDownloadBytes(settings.llmModel)
        let remaining = estimate.map { max($0 - (model?.cacheSize ?? 0), 0) }
        return String(
            format: L("model.download_confirm_message"),
            model?.displayName ?? settings.llmModel,
            remaining.map(ModelCatalog.formatBytes) ?? L("download.unknown"),
            ModelStorage.root.path
        )
    }

    var canContinueFromModelPrep: Bool {
        if !ProductEdition.current.capabilities.modelDownloads {
            return OfflineModelBundle.validate().isReady
        }
        return skippedModelDownload ||
            catalog.llmModels.first(where: { $0.id == settings.llmModel })?.status == .downloaded ||
            catalog.llmModels.first(where: { $0.id == settings.llmModel })?.status == .ready
    }

    var readyPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(L("onboarding.all_set"))
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(L("onboarding.ready_body"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            HStack(spacing: 6) {
                Image(systemName: "fn")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text(L("onboarding.hold_hint"))
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
        }
        .padding(32)
    }

    var navigationBar: some View {
        HStack {
            if step > 0 {
                Button(L("common.back")) { step -= 1 }
                    .controlSize(.regular)
            }
            Spacer()
            stepIndicator
            Spacer()
            if step == 2 {
                Button(L("common.continue")) { step += 1 }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinueFromModelPrep)
            } else if step < 3 {
                Button(L("common.continue")) { step += 1 }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("onboarding.get_started")) { onComplete() }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
