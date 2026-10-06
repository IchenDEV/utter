#if os(iOS)
import Foundation
import UtterRuntime
import UtterContracts
import UtterData
import UtterProcessing
import UtterSession
import UtterModels
import UtterMLX
import UtterKeyboardBridge

extension MobileController {
    func install() async throws {
        // Catalog names and hints are localized by UtterContracts, which defaults to Chinese; follow the system language like the app does.
        Loc.use(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english)
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true).appendingPathComponent("UtterMobile", isDirectory: true)
        let registrations = [DataPlugins.settings(defaults: .standard), DataPlugins.notifications(),
                             DataPlugins.history(directoryURL: directory, reportError: { _ in }),
                             DataPlugins.dictionary(directoryURL: directory), ProcessingPlugins.preparation(),
                             DataPlugins.diagnostics(MobileDiagnostics()), DataPlugins.lexicons(),
                             ModelPlugins.artifacts(), ModelPlugins.files(), ModelPlugins.resourceAccess(),
                             ModelPlugins.speechProviders(), ModelPlugins.textProviders(), MLXPlugins.modelDownloads(),
                             MLXPlugins.qwenSpeech(), MLXPlugins.fireredSpeech(), MLXPlugins.megaSpeech(), MLXPlugins.text(),
                             ModelPlugins.catalog(), mobileWorkflow(), SessionPlugins.execution()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(registrations))
        do {
            try await runtime.start(registrations.map { PluginSelection($0.descriptor.id) })
            try runtime.service(DataServices.settings).update {
                $0.uiLanguage = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? .chinese : .english
            }
            try Task.checkCancellation()
            let execution = try runtime.service(SessionServices.execution)
            try bridge?.reset()
            self.runtime = runtime; self.execution = execution
            factory = try runtime.service(SessionServices.workflows) as? MobileWorkflowFactory
            if let factory { polishService.configure(files: factory.files, access: factory.access) }
            observation = execution.observe { [weak self] snapshot in self?.project(snapshot) }
            let catalog = try runtime.service(ModelServices.catalog)
            modelObservation = catalog.observe { [weak self] in self?.updateModels($0) }
            updateModels(catalog.snapshot)
        } catch { try? await runtime.stop(); throw error }
    }

    private func mobileWorkflow() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "mobile.workflow",
            requires: [DataServices.dictionary.required, DataServices.lexicons.required, ProcessingServices.preparation.required,
                       ModelServices.files.required, ModelServices.resourceAccess.required],
            provides: [SessionServices.workflows.reference])) { context, _ in
            let factory = MobileWorkflowFactory(capture: MobileCapture(), dictionary: try context.require(DataServices.dictionary),
                                                preparation: try context.require(ProcessingServices.preparation),
                                                files: try context.require(ModelServices.files),
                                                access: try context.require(ModelServices.resourceAccess),
                                                lexicons: try context.require(DataServices.lexicons))
            try context.provide(SessionServices.workflows, value: factory)
        }
    }

    private func project(_ snapshot: SessionExecutionSnapshot) {
        guard snapshot.id == status.requestID else { return }
        switch snapshot.phase {
        case .created, .preparing: status.phase = .preparing
        case .recording: status.phase = .recording; showDraft(snapshot.transcript)
        case .transcribing, .processing, .delivering: status.phase = .processing; showDraft(snapshot.transcript)
        case .completed:
            status.phase = .result; status.text = snapshot.text; status.expiresAt = Date().addingTimeInterval(120)
            beginPolish(snapshot.text)
        case .cancelled: status.phase = .cancelled; discardDraft()
        case .failed: status.phase = .failed; status.errorKey = "ios.error.recognition"; discardDraft()
        case nil: return
        }
        if !status.isBusy { watchdog?.cancel(); watchdog = nil }
        publish()
        if status.phase == .result { monitorResult() }
        else { resultMonitor?.cancel(); resultMonitor = nil }
    }

    private func discardDraft() { status.text = ""; status.polish = nil; status.polished = nil; polishTask?.cancel(); polishTask = nil }

    /// Live text while speaking; an empty update never erases what was already shown.
    private func showDraft(_ text: String) { if !text.isEmpty { status.text = text } }

    /// Rewrites a keyboard dictation with the on-device language model once the raw text is final. The raw
    /// text is already published, so a slow or failed rewrite costs the user nothing.
    private func beginPolish(_ text: String) {
        polishTask?.cancel(); polishTask = nil
        status.polish = nil; status.polished = nil
        let request = status.requestID
        #if DEBUG
        if diagnosticText != nil, polishEnabled, activeLease != nil {
            status.polish = .pending
            polishTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                guard let self, !Task.isCancelled, self.status.requestID == request, self.status.phase == .result else { return }
                self.status.polished = text + "."; self.status.polish = .done; self.publish()
            }
            return
        }
        #endif
        guard polishEnabled, activeLease != nil, polishAvailable else { return }
        status.polish = .pending
        let terms = dictionaryEntries.map(\.replacement)
        let model = polishModel
        polishTask = Task { [weak self] in
            let language = self?.language ?? "zh"
            let polished: String?
            if model == "system" { polished = await MobilePolisher.polish(text, language: language, protectedTerms: terms) }
            else if let service = self?.polishService {
                polished = await service.polish(text, language: language, protectedTerms: terms, modelID: model)
            } else { polished = nil }
            guard let self, !Task.isCancelled, self.status.requestID == request, self.status.phase == .result else { return }
            if let polished { self.status.polished = polished; self.status.polish = .done } else { self.status.polish = .failed }
            self.publish()
        }
    }

    public var dictionaryEntries: [MobileDictionaryEntry] {
        guard let dictionary = try? runtime?.service(DataServices.dictionary) else { return [] }
        return dictionary.entries.map { MobileDictionaryEntry(id: $0.id, original: $0.original, replacement: $0.replacement) }
    }
    public func addDictionaryEntry(original: String, replacement: String) -> Bool {
        guard !clearing, let dictionary = try? runtime?.service(DataServices.dictionary),
              dictionary.addEntry(original: original, replacement: replacement) != nil else { return false }
        objectWillChange.send()
        return true
    }
    public func deleteDictionaryEntry(_ id: UUID) {
        guard !clearing, let dictionary = try? runtime?.service(DataServices.dictionary) else { return }
        dictionary.removeEntry(id: id)
        objectWillChange.send()
    }
}

public struct MobileDictionaryEntry: Identifiable {
    public let id: UUID
    public let original: String
    public let replacement: String
}
#endif
