import AppKit
import SwiftUI

extension ModelManagementView {
    var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("model.storage.title"), systemImage: "externaldrive")
                .font(.headline)

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

    var preloadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("model.preload.title"), systemImage: "bolt.circle")
                .font(.headline)

            Toggle(L("model.preload.speech"), isOn: $settings.preloadSpeechModelOnLaunch)
                .help(L("model.preload.speech_help"))

            Toggle(L("model.preload.formatting"), isOn: $settings.preloadFormattingModelOnLaunch)
                .help(L("model.preload.formatting_help"))
        }
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

    var mimoASRSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("mimo_asr.config_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            modelList(
                catalog.asrModels(for: .mimo),
                activeID: settings.mimoASRModel,
                type: .asr
            )
        }
    }

    var llmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("model.text_formatting"), systemImage: "brain")
                .font(.headline)

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
        }
        let customModels = catalog.llmModels.filter { $0.family == nil }
        if !customModels.isEmpty {
            Text(L("model.custom_local"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
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

    func syncSelectedFamilyFromActiveModel() {
        guard !settings.useRemoteLLM else { return }
        if let family = catalog.llmModels.first(where: { $0.id == settings.llmModel })?.family {
            selectedModelFamily = family
        }
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
