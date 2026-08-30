import AppKit
import SwiftUI

extension ModelManagementView {
    var deviceInfoSection: some View {
        let info = DeviceCapability.current
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                deviceInfoItem(
                    icon: "memorychip",
                    label: L("device.chip"),
                    value: info.chipDisplayName
                )
                Divider().frame(height: 28)
                deviceInfoItem(
                    icon: "memorychip.fill",
                    label: L("device.ram"),
                    value: info.ramDisplayText
                )
                Divider().frame(height: 28)
                deviceInfoItem(
                    icon: "gpu",
                    label: "GPU",
                    value: info.gpuDisplayText
                )
                Divider().frame(height: 28)
                deviceInfoItem(
                    icon: "internaldrive",
                    label: L("device.disk_available"),
                    value: info.diskAvailableText
                )
            }
        }
    }

    private func deviceInfoItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ModelStorage.root.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            Text(String(
                format: L("model.storage.usage"),
                ModelCatalog.formatBytes(knownStorageBytes)
            ))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(L("model.storage.choose")) {
                    chooseModelStorageLocation()
                }
                Button(L("model.storage.reveal")) {
                    NSWorkspace.shared.activateFileViewerSelecting([ModelStorage.root])
                }
                Button(L("model.storage.reset")) {
                    requestModelStoragePath(ModelStorage.defaultRoot.path)
                }
            }
            .controlSize(.small)
            .disabled(hasActiveDownloads)
        }
    }

    @ViewBuilder
    var preloadSection: some View {
        Toggle(L("model.preload.speech"), isOn: $settings.preloadSpeechModelOnLaunch)
            .help(L("model.preload.speech_help"))

        Toggle(L("model.preload.formatting"), isOn: $settings.preloadFormattingModelOnLaunch)
            .help(L("model.preload.formatting_help"))
    }

    var whisperSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            modelList(catalog.whisperModels, activeID: settings.whisperModel, type: .whisper)
            Button(L("model.import_local")) {
                importLocalWhisper()
            }
            .controlSize(.small)
        }
    }

    var volcSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("volc.config_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Picker(L("volc.model"), selection: $settings.volcResourceId) {
                ForEach(VolcASRModel.allCases) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }

            TextField(L("volc.app_key"), text: $settings.volcAppKey)
                .textFieldStyle(.roundedBorder)
            SecureField(L("volc.access_key"), text: $settings.volcAccessKey)
                .textFieldStyle(.roundedBorder)
            TextField(L("volc.resource_id"), text: $settings.volcResourceId)
                .textFieldStyle(.roundedBorder)
        }
    }

    var qwenASRSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("qwen_asr.config_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            modelList(
                catalog.asrModels(for: .qwen3),
                activeID: settings.qwenASRModel,
                type: .asr
            )
        }
    }

    var llmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.lastFormattingDurationSeconds > 0 {
                HStack(spacing: 8) {
                    Text(L("model.last_formatting"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(String(format: L("model.last_formatting_value"), appState.lastFormattingDurationSeconds))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("model.family.title"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                familyPicker
            }

            if settings.useRemoteLLM {
                RemoteLLMConfigView()
            } else if settings.localLLMBackend == .espresso {
                espressoLLMSection
            } else {
                localLLMModelsSection
            }
        }
        .alert(importErrorMessage.isEmpty ? L("model.import_invalid") : L("model.import_failed"), isPresented: $showImportError) {
            Button(L("common.ok")) { }
        } message: {
            if !importErrorMessage.isEmpty { Text(importErrorMessage) }
        }
    }

    @ViewBuilder
    var localLLMModelsSection: some View {
        if let family = selectedModelFamily {
            let familyModels = catalog.llmModels.filter { $0.family == family }
            groupedLLMModelList(familyModels, activeID: settings.llmModel)
        } else {
            let customModels = catalog.llmModels.filter { $0.family == nil }
            if !customModels.isEmpty {
                modelList(customModels, activeID: settings.llmModel, type: .llm)
            }

            HStack(spacing: 8) {
                TextField(L("model.custom_id_placeholder"), text: $customLLMInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button(L("common.add")) {
                    catalog.addCustomLLM(customLLMInput)
                    customLLMInput = ""
                }
                .controlSize(.small)
                .disabled(customLLMInput.isEmpty)
            }
            Button(L("model.import_local")) {
                importLocalLLM()
            }
            .controlSize(.small)
        }
    }

    var espressoLLMSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Espresso", systemImage: "neural.engine")
                .font(.system(size: 12, weight: .semibold))

            Text(L("model.espresso.description"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(settings.espressoModelPath.isEmpty
                    ? L("model.espresso.no_bundle")
                    : settings.espressoModelPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(settings.espressoModelPath.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                Button(L("model.espresso.choose")) {
                    chooseEspressoBundle()
                }
                .controlSize(.small)
            }

            Label(L("model.espresso.private_api_warning"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        }
    }

    func syncSelectedFamilyFromActiveModel() {
        guard !settings.useRemoteLLM, settings.localLLMBackend == .mlx else { return }
        let activeFamily = catalog.llmModels
            .first(where: { $0.id == settings.llmModel })
            .map(\.family)
        selectedModelFamily = FormattingModelType.resolvedLocalSelection(
            pending: nil,
            activeFamily: activeFamily
        ).family
    }

    func syncSelectedFamilyAfterBackendChange() {
        guard !settings.useRemoteLLM, settings.localLLMBackend == .mlx else { return }
        let activeFamily = catalog.llmModels
            .first(where: { $0.id == settings.llmModel })
            .map(\.family)
        selectedModelFamily = FormattingModelType.resolvedLocalSelection(
            pending: pendingFormattingTypeAfterBackendChange,
            activeFamily: activeFamily
        ).family
        pendingFormattingTypeAfterBackendChange = nil
    }

    /// Split a family's models into recommended (top), standard, and legacy (folded) tiers.
    @ViewBuilder
    func groupedLLMModelList(
        _ models: [ModelCatalog.ModelEntry], activeID: String
    ) -> some View {
        let recommended = models.filter { $0.tier == .recommended }
        let standard = models.filter { $0.tier == .standard }
        let legacy = models.filter { $0.tier == .legacy }

        VStack(spacing: 8) {
            if !recommended.isEmpty {
                modelList(recommended, activeID: activeID, type: .llm)
            }
            if !standard.isEmpty {
                modelList(standard, activeID: activeID, type: .llm)
            }
            if !legacy.isEmpty {
                DisclosureGroup(isExpanded: $showLegacyModels) {
                    modelList(legacy, activeID: activeID, type: .llm)
                        .padding(.top, 4)
                } label: {
                    Text("\(L("model.legacy_group")) (\(legacy.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
