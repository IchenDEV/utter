import SwiftUI
import AppKit

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
    let benchmarkEngine = LLMEngine()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                storageSection
                Divider()
                preloadSection
                Divider()
                enginePickerSection
                if settings.speechEngine == .whisper {
                    whisperSection
                }
                if settings.speechEngine == .volc {
                    volcSection
                }
                if settings.speechEngine == .qwen3 {
                    qwenASRSection
                }
                if settings.speechEngine == .mimo {
                    mimoASRSection
                }
                Divider()
                llmSection
            }
            .padding(20)
        }
        .onAppear {
            catalog.refreshStatus()
            syncSelectedFamilyFromActiveModel()
        }
        .onChange(of: settings.llmModel) { _, _ in syncSelectedFamilyFromActiveModel() }
        .onChange(of: settings.localASRPythonPath) { _, _ in onUnloadLocalASR?() }
        .onChange(of: settings.mimoASRRepoPath) { _, _ in onUnloadLocalASR?() }
        .onChange(of: settings.qwenASRModel) { _, _ in onUnloadLocalASR?() }
        .onChange(of: settings.mimoASRModel) { _, _ in onUnloadLocalASR?() }
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
            updateModelStoragePath(url.path)
        }
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
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path) else {
                importErrorMessage = ""
                showImportError = true
                return
            }
            onUnloadLLM?()
            catalog.addLocalLLM(url)
        }
    }

    private func isValidWhisperFolder(_ url: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("\(name).mlmodelc").path)
                || FileManager.default.fileExists(atPath: url.appendingPathComponent("\(name).mlpackage").path)
        }
    }
}
