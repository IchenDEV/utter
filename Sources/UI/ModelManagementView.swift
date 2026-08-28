import SwiftUI
import AppKit
import ESPRuntime

struct ModelManagementView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @StateObject var catalog = ModelCatalog.shared

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?
    var onLoadLLM: (() -> Void)?
    var onUnloadLocalASR: (() -> Void)?

    @State var customLLMInput = ""
    @State var showImportError = false
    @State var importErrorMessage = ""
    @State var selectedModelFamily: ModelCatalog.ModelFamily? = .qwen
    @State var showLegacyModels = false
    @State var pendingModelAction: PendingModelAction?
    let benchmarkEngine = LLMEngine()

    var body: some View {
        VStack(spacing: 0) {
            SettingsPageHeader(
                kind: .models,
                title: L("settings.page.models.title"),
                subtitle: L("settings.page.models.subtitle")
            ) {
                SettingsPageBadge(title: settings.speechEngine.label, symbol: "waveform")
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if hasActiveDownloads {
                        SettingsPanel { activeDownloadsSection }
                    }

                    SettingsPanel { deviceInfoSection }

                    SettingsPanel {
                        enginePickerSection
                        Divider().padding(.vertical, 4)
                        selectedRecognitionConfiguration
                    }

                    SettingsPanel { llmSection }
                    SettingsPanel { preloadSection }
                    SettingsPanel { storageSection }
                }
                .padding(20)
            }
        }
        .settingsPageSurface()
        .onAppear {
            catalog.refreshStatus(recheckingErrors: true)
            syncSelectedFamilyFromActiveModel()
        }
        .onChange(of: settings.llmModel) { _, _ in syncSelectedFamilyFromActiveModel() }
        .onChange(of: settings.localLLMBackend) { _, _ in syncSelectedFamilyFromActiveModel() }
        .onChange(of: settings.qwenASRModel) { _, _ in onUnloadLocalASR?() }
        .alert(item: $pendingModelAction, content: modelActionAlert)
    }

    @ViewBuilder
    private var selectedRecognitionConfiguration: some View {
        switch settings.speechEngine {
        case .whisper:
            whisperSection
        case .volc:
            volcSection
        case .qwen3:
            qwenASRSection
        case .mimo:
            Text(L("model.apple_managed_by_system"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .apple:
            Text(L("model.apple_managed_by_system"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension ModelManagementView {
    func chooseModelStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = ModelStorage.root
        panel.message = L("model.storage.choose")
        if panel.runModal() == .OK, let url = panel.url {
            requestModelStoragePath(url.path)
        }
    }

    func requestModelStoragePath(_ path: String) {
        let currentURL = ModelStorage.root.standardizedFileURL
        let nextURL = URL(fileURLWithPath: path).standardizedFileURL
        guard currentURL != nextURL else { return }

        let currentSize = ModelStorage.directorySize(at: currentURL)
        if currentSize > 0 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("model.storage.change_confirm_title")
            alert.informativeText = String(
                format: L("model.storage.change_confirm_message"),
                ModelCatalog.formatBytes(currentSize),
                currentURL.path,
                nextURL.path
            )
            alert.addButton(withTitle: L("common.cancel"))
            alert.addButton(withTitle: L("model.storage.switch_anyway"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }

        updateModelStoragePath(nextURL.path)
    }

    func updateModelStoragePath(_ path: String) {
        onUnloadWhisper?()
        onUnloadLLM?()
        onUnloadLocalASR?()
        settings.modelStoragePath = path
        catalog.refreshStatus(recheckingErrors: true)
    }

    func importLocalWhisper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("model.import_local")
        if panel.runModal() == .OK, let url = panel.url {
            guard isValidWhisperFolder(url) else {
                importErrorMessage = L("model.import_invalid_whisper")
                showImportError = true
                return
            }
            onUnloadWhisper?()
            catalog.addLocalWhisper(url)
        }
    }

    func importLocalLLM() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("model.import_local")
        if panel.runModal() == .OK, let url = panel.url {
            guard ModelStorage.llmRepoIsComplete(at: url) else {
                importErrorMessage = ""
                showImportError = true
                return
            }
            onUnloadLLM?()
            catalog.addLocalLLM(url)
        }
    }

    func chooseEspressoBundle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("model.espresso.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            _ = try ESPRuntimeBundle.open(at: url)
            onUnloadLLM?()
            settings.espressoModelPath = url.path
            settings.localLLMBackend = .espresso
            settings.useRemoteLLM = false
            onLoadLLM?()
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func isValidWhisperFolder(_ url: URL) -> Bool {
        ModelStorage.whisperModelIsComplete(at: url)
    }
}
