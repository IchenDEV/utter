#if os(iOS)
import Foundation
import Combine
import AVFoundation
import UtterRuntime
import UtterContracts
import UtterData
import UtterProcessing
import UtterSession
import UtterAppleSpeech
import UtterKeyboardBridge

@MainActor
public final class MobileController: ObservableObject {
    @Published public internal(set) var status = VoiceStatus()
    public let bridge: SharedVoiceBridge?
    @Published public var language = UserDefaults.standard.string(forKey: "mobile.language") ?? "zh" {
        didSet { UserDefaults.standard.set(language, forKey: "mobile.language") }
    }
    /// Rewrite finished keyboard dictations with the on-device language model.
    @Published public var polishEnabled = UserDefaults.standard.object(forKey: "mobile.polish") == nil || UserDefaults.standard.bool(forKey: "mobile.polish") {
        didSet { UserDefaults.standard.set(polishEnabled, forKey: "mobile.polish") }
    }
    /// "system" is Apple's on-device model; any other value is the id of a downloaded text model.
    @Published public internal(set) var polishModel = UserDefaults.standard.string(forKey: "mobile.polish.model") ?? "system"
    public var polishAvailable: Bool {
        polishModel == "system" ? MobilePolisher.isAvailable : models.contains { $0.id == polishModel && $0.downloaded }
    }
    public var polishModelName: String {
        polishModel == "system" ? L("ios.models.system_polish") : models.first { $0.id == polishModel }?.name ?? polishModel
    }
    public var systemPolishAvailable: Bool { MobilePolisher.isAvailable }
    let polishService = LocalPolisher()
    @Published public internal(set) var isEnabled = false
    /// True only while the app holds a system capability that lets it serve keyboard commands in the background.
    public private(set) var standbyActive = false
    @Published public internal(set) var models: [MobileModel] = []
    @Published public internal(set) var selectedModel = UserDefaults.standard.string(forKey: "mobile.model") ?? "apple"
    @Published public internal(set) var libraryError: String?
    @Published public internal(set) var applePreparing = false
    @Published public internal(set) var appleReady = false
    @Published public internal(set) var modelMutation: String?
    var appleTask: Task<Void, Error>?
    var appleStatusRevision = 0
    var libraryTask: Task<Void, Error>?
    var modelObservation: UUID?
    var disabling = false
    @Published public internal(set) var clearing = false
    var runtime: PluginRuntime?
    var execution: (any SessionExecutionService)?
    var factory: MobileWorkflowFactory?
    var observation: UUID?
    var activeLease: KeyboardLease?
    var watchdog: Task<Void, Never>?
    var resultMonitor: Task<Void, Never>?
    var polishTask: Task<Void, Never>?
    var activation: Task<Void, Error>?
    #if DEBUG
    var diagnosticText: String?
    #endif

    public init(bridge: SharedVoiceBridge?) {
        self.bridge = bridge
        try? bridge?.publish(status)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UtterRecordings")
        try? FileManager.default.removeItem(at: directory)
    }

    public func enable() async {
        guard !isEnabled, activation == nil, !disabling, !clearing, modelMutation == nil, !applePreparing else { return }
        #if DEBUG
        diagnosticText = nil
        #endif
        let locale = Locale(identifier: language == "en" ? "en-US" : "zh-CN")
        do {
            try await activate {
                guard await AVAudioApplication.requestRecordPermission() else { throw MobileError.microphoneDenied }
                if self.selectedModel == "apple" { try await AppleSpeechAnalyzer.prepare(locale: locale) }
                else { try self.requireDownloadedModel() }
            }
        } catch {}
    }

    private func activate(prepare: @escaping @MainActor () async throws -> Void) async throws {
        guard !isEnabled, activation == nil, !disabling, !clearing, modelMutation == nil, !applePreparing else { throw BridgeError.invalidTarget }
        status.phase = .preparing; status.errorKey = nil; publish()
        let task = Task {
            try await ensureLibrary()
            try Task.checkCancellation()
            try await prepare()
            try Task.checkCancellation()
            isEnabled = true
            status = VoiceStatus(generation: UUID(), phase: .ready)
            publish()
        }
        activation = task
        defer { activation = nil }
        do { try await task.value }
        catch {
            if error is CancellationError { status.phase = .cancelled; status.errorKey = nil }
            else { status.phase = .failed; status.errorKey = error as? MobileError == .microphoneDenied ? "ios.error.microphone" : "ios.error.local_unavailable" }
            publish()
            throw error
        }
    }

    public func disable() async {
        guard !disabling else { return }
        disabling = true
        defer { disabling = false }
        activation?.cancel()
        if let activation { _ = await activation.result }
        watchdog?.cancel(); watchdog = nil
        resultMonitor?.cancel(); resultMonitor = nil
        polishTask?.cancel(); polishTask = nil
        execution?.cancel()
        await execution?.stop()
        isEnabled = false; activeLease = nil; standbyActive = false
        #if DEBUG
        diagnosticText = nil
        #endif
        status = VoiceStatus(); publish()
        try? bridge?.reset()
    }

    public func beginLocal(id: UUID) throws { try begin(id: id, lease: nil) }
    public func stop() async { await execution?.stop() }
    public func cancel() async {
        if let activation {
            activation.cancel()
            _ = await activation.result
        }
        execution?.cancel(); await execution?.stop()
    }

    public func discardResult() {
        guard !status.isBusy else { return }
        resultMonitor?.cancel(); resultMonitor = nil
        polishTask?.cancel(); polishTask = nil
        status.text = ""; status.expiresAt = nil; status.polish = nil; status.polished = nil
        status.phase = isEnabled ? .ready : .disabled
        publish()
    }

    public func refreshResult() {
        guard status.phase == .result else { return }
        guard status.expiresAt ?? .distantPast > Date() else { discardResult(); return }
        guard let bridge else { return }
        do {
            guard let current = try bridge.status(), current.generation == status.generation,
                  current.requestID == status.requestID, current.phase == .result, !current.text.isEmpty else {
                discardResult(); return
            }
        } catch {
            resultMonitor?.cancel(); resultMonitor = nil
            status.text = ""; status.expiresAt = nil; status.phase = .failed; status.errorKey = "ios.error.bridge"
            publish()
        }
    }

    func monitorResult() {
        resultMonitor?.cancel()
        let request = status.requestID
        resultMonitor = Task { [weak self] in
            while let self, !Task.isCancelled, self.status.phase == .result, self.status.requestID == request {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self.refreshResult()
            }
        }
    }

    public func clearLocalData() async -> Bool {
        guard !clearing, !disabling, modelMutation == nil else { return false }
        clearing = true
        appleStatusRevision += 1
        defer { clearing = false }
        await disable()
        appleTask?.cancel()
        if let appleTask { _ = await appleTask.result }
        libraryTask?.cancel()
        if let libraryTask { _ = await libraryTask.result }
        do { try await runtime?.stop() }
        catch { libraryError = "ios.error.shutdown"; return false }
        runtime = nil; execution = nil; factory = nil; models = []; modelObservation = nil
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false)
            let paths = [support.appendingPathComponent("UtterMobile"), DataLocations.models,
                         FileManager.default.temporaryDirectory.appendingPathComponent("UtterRecordings")]
            for path in paths where FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            try bridge?.reset()
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            language = "zh"; selectedModel = "apple"; appleReady = false
            return true
        } catch { status.phase = .failed; status.errorKey = "ios.error.clear_data"; publish(); return false }
    }

    public func perform(_ requestID: UUID) async throws {
        guard let bridge, execution != nil else { throw MobileError.notEnabled }
        let command = try bridge.take(requestID, generation: status.generation)
        switch command.action {
        case .start: try begin(id: command.id, lease: command.lease)
        case .stop, .cancel:
            guard status.leaseID == command.lease.id, status.documentID == command.lease.documentID else { throw BridgeError.invalidTarget }
            if command.action == .cancel { execution?.cancel() }
            await execution?.stop()
        }
    }

    func begin(id: UUID, lease: KeyboardLease?) throws {
        guard isEnabled, !disabling, !clearing, modelMutation == nil, let execution else { throw MobileError.notEnabled }
        guard !status.isBusy else { throw BridgeError.invalidTarget }
        let previous = status
        activeLease = lease
        status.requestID = id; status.leaseID = lease?.id; status.documentID = lease?.documentID
        status.text = ""; status.errorKey = nil; status.expiresAt = nil; status.polish = nil; status.polished = nil
        polishTask?.cancel(); polishTask = nil
        if polishEnabled, polishModel != "system", polishAvailable { polishService.warmUp(modelID: polishModel) }
        factory?.language = language
        factory?.modelID = selectedModel
        factory?.maximumDuration = recordingLimit
        factory?.sensitivity = audioSensitivity
        factory?.industry = industryLexicon
        var input: SessionInput = .local
        #if DEBUG
        if let diagnosticText { input = .text(diagnosticText) }
        #endif
        do { try execution.start(SessionIntent(id: id, input: input)) }
        catch { status = previous; activeLease = nil; throw error }
        watchdog?.cancel()
        if let lease {
            watchdog = Task { [weak self] in
                while let self, self.status.isBusy, !Task.isCancelled {
                    do {
                        guard let current = try self.bridge?.lease(lease.id), current.generation == lease.generation,
                              current.documentID == lease.documentID else { await self.cancel(); break }
                        try await Task.sleep(for: .seconds(1))
                    } catch { await self.cancel(); break }
                }
            }
        }
    }

    public func setStandby(_ active: Bool) {
        standbyActive = active && isEnabled
        publish()
    }

    public func beat() { if standbyActive { publish() } }

    func publish() {
        status.updatedAt = Date()
        status.heartbeat = standbyActive && isEnabled ? Date() : nil
        do { try bridge?.publish(status) }
        catch {
            execution?.cancel()
            status.text = ""; status.phase = .failed; status.errorKey = "ios.error.bridge"
            try? bridge?.publish(status)
        }
    }

    #if DEBUG
    public func enableBridgeDiagnostic(text: String) async throws {
        try await activate { self.diagnosticText = text }
        // The foreground simulator host stands in for background standby; it keeps the heartbeat fresh itself.
        setStandby(true)
    }
    #endif
}
#endif
