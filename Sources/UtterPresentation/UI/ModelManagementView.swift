import UtterMediaContracts
import UtterPresentationContracts
import UtterContracts
import SwiftUI
import AppKit

struct ModelManagementView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @ObservedObject var catalog: ModelCatalogProjection
    let storage: any ModelStorageService
    @ObservedObject var lifecycle: ModelLifecycleProjection
    let remoteConnection: (any RemoteConnectionService)?

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?
    var onLoadLLM: (() -> Void)?
    var onBenchmarkLLM: ((String) async throws -> ModelBenchmarkResult)?
    var onUnloadLocalASR: (() -> Void)?

    @State var customLLMInput = ""
    @State var showImportError = false
    @State var importErrorMessage = ""
    @State var selectedModelFamily: ModelCatalogProjection.ModelFamily? = .qwen
    @State var showLegacyModels = false
    @State var pendingModelAction: PendingModelAction?
    @State var pendingFormattingTypeAfterBackendChange: FormattingModelType?

    var body: some View {
        Form {
            if hasActiveDownloads {
                Section(String(format: L("model.downloads_active"), activeDownloads.count)) {
                    activeDownloadsSection
                }
            }

            Section(L("device.title")) {
                deviceInfoSection
            }

            Section(L("model.speech_recognition")) {
                enginePickerSection
                selectedRecognitionConfiguration
            }

            Section(L("model.text_formatting")) {
                llmSection
            }

            Section(L("model.preload.title")) {
                preloadSection
            }

            Section(L("model.storage.title")) {
                storageSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsPageSurface()
        .onAppear {
            catalog.refreshStatus(recheckingErrors: true)
            syncSelectedFamilyFromActiveModel()
        }
        .onChange(of: settings.llmModel) { _, _ in syncSelectedFamilyFromActiveModel() }
        .onChange(of: settings.localLLMBackend) { _, _ in
            syncSelectedFamilyAfterBackendChange()
        }
        .onChange(of: settings.qwenASRModel) { _, _ in onUnloadLocalASR?() }
        .onChange(of: lifecycle.snapshot.error) { _, error in
            if let error { importErrorMessage = error; showImportError = true }
        }
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
        case .firered, .megaASR:
            qwenASRSection
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
        panel.directoryURL = storage.root
        panel.message = L("model.storage.choose")
        if panel.runModal() == .OK, let url = panel.url {
            requestModelStoragePath(url.path)
        }
    }

    func requestModelStoragePath(_ path: String) {
        let currentURL = storage.root.standardizedFileURL
        let nextURL = URL(fileURLWithPath: path).standardizedFileURL
        guard currentURL != nextURL else { return }

        let currentSize = storage.directorySize(at: currentURL)
        if currentSize > 0 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("model.storage.change_confirm_title")
            alert.informativeText = String(
                format: L("model.storage.change_confirm_message"),
                ModelCatalogProjection.formatBytes(currentSize),
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
            guard storage.llmRepoIsComplete(at: url) else {
                importErrorMessage = L("model.import_invalid")
                showImportError = true
                return
            }
            onUnloadLLM?()
            catalog.addLocalLLM(url)
        }
    }

    func chooseANEModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("model.espresso.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { @MainActor in
            do {
                try await lifecycle.validateBundle(at: url)
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
    }

    private func isValidWhisperFolder(_ url: URL) -> Bool {
        storage.whisperModelIsComplete(at: url)
    }
}
