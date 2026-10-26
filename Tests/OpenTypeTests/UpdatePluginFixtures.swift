import Foundation
import UtterContracts
import UtterRuntime
@testable import UtterUpdates

@MainActor
final class UpdateFakeExecution: SessionExecutionService {
    private(set) var snapshot = SessionExecutionSnapshot()
    private var observers: [UUID: (SessionExecutionSnapshot) -> Void] = [:]
    var observerCount: Int { observers.count }

    func setBusy(_ busy: Bool) {
        snapshot = SessionExecutionSnapshot(isBusy: busy)
        for observer in Array(observers.values) { observer(snapshot) }
    }

    func observe(_ callback: @escaping (SessionExecutionSnapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    @discardableResult func requestStop(_ id: UUID, at timestamp: Duration?) -> Bool { false }
    func promoteToTranslation(_ id: UUID, reason: HotkeyPromotion) -> Bool { false }
    @discardableResult func applySelectionEdit(sessionID: UUID, proposalID: UUID) -> Bool { false }
    func authorizeRemoteDisclosure(_ intentID: UUID) throws {}
    func declineRemoteDisclosure(_ intentID: UUID) {}
    func reserve(_ intent: SessionIntent) throws {}
    func activate(_ id: UUID, input: SessionInput?) throws {}
    func waitForRecording(_ id: UUID) async throws {}
    func waitForCompletion(_ id: UUID) async throws -> SessionExecutionSnapshot { snapshot }
    func start(_ intent: SessionIntent) throws {}
    func stop() async {}
    func stop(_ id: UUID) async {}
    func cancel() {}
    func cancel(_ id: UUID) {}
    func observeProgress(_ callback: @escaping (SessionIntent, SessionExecutionSnapshot) -> Void) -> UUID { UUID() }
    func removeProgressObserver(_ id: UUID) {}
    func observeSettlement(_ callback: @escaping (SessionIntent, Result<SessionCompletion, Error>) -> Void) -> UUID { UUID() }
    func removeSettlementObserver(_ id: UUID) {}
}

@MainActor
final class UpdateFakeCatalog: ModelCatalogService {
    private(set) var snapshot = ModelCatalogSnapshot(whisper: [], text: [], speech: [])
    private var observers: [UUID: (ModelCatalogSnapshot) -> Void] = [:]
    var observerCount: Int { observers.count }

    func setDownloading(_ downloading: Bool) {
        var entry = CatalogModelEntry(id: "model", displayName: "model", hint: "", family: nil)
        entry.status = downloading ? .downloading : .ready
        snapshot = ModelCatalogSnapshot(whisper: [entry], text: [], speech: [])
        for observer in Array(observers.values) { observer(snapshot) }
    }

    func observe(_ callback: @escaping (ModelCatalogSnapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    func refreshStatus(recheckingErrors: Bool) {}
    func downloadWhisper(_ id: String) async {}
    func downloadLLM(_ id: String) async {}
    func downloadASR(_ id: String, onProgress: ((DownloadProgressInfo) -> Void)?) async {}
    func cancelDownload(_ id: String, kind: ModelDownloadKind) {}
    func deleteWhisper(_ id: String) async {}
    func deleteLLM(_ id: String) async {}
    func deleteASR(_ id: String) async {}
    func addCustomLLM(_ modelID: String) {}
    func addLocalWhisper(_ url: URL) {}
    func addLocalLLM(_ url: URL) {}
    func updateWhisperStatus(_ id: String, status: CatalogModelStatus, detail: String) {}
    func updateLLMStatus(_ id: String, status: CatalogModelStatus, detail: String) {}
    func asrModels(for engine: SpeechEngineType) -> [CatalogModelEntry] { [] }
    func estimatedLLMDownloadBytes(_ id: String) -> Int64? { nil }
    func estimatedASRDownloadBytes(_ id: String) -> Int64? { nil }
}

@MainActor
final class UpdateFakeDriver: UpdateDriver {
    var startedWith: [Bool] = []
    var automaticChecks: [Bool] = []
    var stops = 0
    var hooks: UpdateDriverHooks?
    func start(automaticChecks: Bool) throws { startedWith.append(automaticChecks) }
    func setAutomaticChecks(_ enabled: Bool) { automaticChecks.append(enabled) }
    func checkForUpdates() {}
    func stop() { stops += 1 }
}

@MainActor
struct UpdatePluginFixture {
    let runtime: PluginRuntime
    let settings: RemotePluginSettings
    let execution = UpdateFakeExecution()
    let catalog = UpdateFakeCatalog()
    let driver = UpdateFakeDriver()
    let driversCreated = Counter()

    @MainActor final class Counter { var value = 0 }

    static let enabledEnvironment = UpdateEnvironment(
        isApplicationBundle: true, isAdHocSigned: false,
        feedURL: "https://example.com/appcast.xml", publicKey: Data(repeating: 9, count: 32).base64EncodedString())

    init(environment: UpdateEnvironment = enabledEnvironment, automaticChecks: Bool = true) throws {
        let settings = RemotePluginSettings()
        settings.values.automaticUpdateChecks = automaticChecks
        self.settings = settings
        let execution = self.execution, catalog = self.catalog, driver = self.driver, created = driversCreated
        let dependencies = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.dependencies",
            provides: [DataServices.settings.reference, IntegrationServices.diagnostics.reference,
                       SessionServices.execution.reference, ModelServices.catalog.reference]
        )) { context, _ in
            try context.provide(DataServices.settings, value: settings)
            try context.provide(IntegrationServices.diagnostics, value: RemotePluginDiagnostics())
            try context.provide(SessionServices.execution, value: execution)
            try context.provide(ModelServices.catalog, value: catalog)
        }
        let plugin = UpdatePlugins.updater(environment: environment) { _, hooks in
            created.value += 1
            driver.hooks = hooks
            return driver
        }
        runtime = PluginRuntime(catalog: try PluginCatalog([dependencies, plugin]))
    }

    func start() async throws {
        try await runtime.start([PluginSelection("fixture.dependencies"), PluginSelection(UpdatePlugins.pluginID)])
    }

    func service() throws -> any UpdateService { try runtime.service(UpdateServices.updater) }
}
