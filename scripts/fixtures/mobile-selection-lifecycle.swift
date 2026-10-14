import Foundation
import OSLog
import UtterContracts
import UtterProcessing
import UtterKeyboardBridge
@testable import UtterSession

@MainActor final class MobileJob: SessionJob {
    let selection: MobileSelectionRequest?
    let language = "zh"
    let dictionary = PersonalDictionarySnapshot(entries: [], editRules: [])
    var selectionOutput: KeyboardSelectionOperation?
    var closing = false
    init(_ request: MobileSelectionRequest) { selection = request }
    func check(_ control: any SessionJobControl) throws {
        try Task.checkCancellation()
        guard control.isCurrent else { throw CancellationError() }
    }
    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        if case .restore = selection!.operation { return try await restoreSelection(control: control) }
        control.update(phase: .recording, transcript: "")
        try await control.waitForStop()
        return try await finishSelection("改礼貌一点", control: control)
    }
    func revoke() { clearSelectionPayload() }
    func close() async {
        closing = true
        // A real resource drain may outlast several keyboard polling ticks.
        try? await Task.sleep(for: .milliseconds(650))
        clearSelectionPayload()
    }
}

@MainActor final class MobileWorkflowFactory: SessionWorkflowFactory {
    var selectionRequest: MobileSelectionRequest?
    var jobs: [MobileJob] = []
    var intents: [SessionIntent] = []
    var completions: [SessionCompletion] = []
    func make(_ intent: SessionIntent) throws -> any SessionJob {
        guard let request = selectionRequest, request.sessionID == intent.id else { throw BridgeError.invalidTarget }
        let job = MobileJob(request); jobs.append(job); intents.append(intent); return job
    }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {
        if case .success(let completion) = result { completions.append(completion) }
        selectionRequest = nil
    }
}

@MainActor final class History: HistoryService {
    var records: [InputRecord] { [] }
    var stats: InputStats { .init(totalInputs: 0, totalRawChars: 0, totalProcessedChars: 0, charsSaved: 0, todayInputs: 0, todayChars: 0, streakDays: 0) }
    var storageAvailable: Bool { true }
    var writes = 0
    func addRecord(_ record: InputRecord) -> UUID { writes += 1; return record.id }
    func replaceRecord(recordID: UUID, processedText: String, context: InputContext?, formatKind: TextFormatKind?) -> UUID? { writes += 1; return nil }
    func updateUserFinalText(recordID: UUID, text: String) { writes += 1 }
    func deleteRecord(_ id: UUID) {}
    func clearAll() {}
    func observe(_ callback: @escaping @MainActor () -> Void) -> UUID { UUID() }
    func removeObserver(_ id: UUID) {}
}

enum MobileError: Error { case notEnabled, localUnavailable }
@MainActor final class MobileController {
    let bridge: SharedVoiceBridge?
    var status: VoiceStatus
    var execution: (any SessionExecutionService)?
    var factory: MobileWorkflowFactory?
    let polishService = LocalPolisher()
    var polishAvailable = true
    var polishModel = "system"
    var watchdog: Task<Void, Never>?
    var activation: Task<Void, Error>?
    init(_ bridge: SharedVoiceBridge) {
        self.bridge = bridge; status = VoiceStatus(phase: .ready); publish()
    }
    // Setup/capture provisioning is an explicit platform seam, not a second production workflow.
    func begin(id: UUID, lease: KeyboardLease?, selection: MobileSelectionRequest? = nil) throws {
        guard !status.isBusy, let execution, let selection else { throw BridgeError.invalidTarget }
        status.requestID = id; status.leaseID = lease?.id; status.documentID = lease?.documentID
        status.selectionMode = true; status.errorKey = nil
        factory!.selectionRequest = selection
        let operation: SessionOperation
        if case .restore(let restoration) = selection.operation { operation = .restoreSelectionEdit(operationID: restoration.operationID) }
        else { operation = .input }
        try execution.start(SessionIntent(id: id, input: .local, mode: .selectionEdit(.custom(""), spokenCommand: ""), operation: operation))
        watchLease(lease)
    }
    func attachKeyboardTarget(_ command: VoiceCommand) throws { throw BridgeError.invalidTarget }
    func publish() {
        status.heartbeat = Date(); status.updatedAt = Date(); try! bridge!.publish(status)
    }
    func beat() { publish() }
}

@MainActor struct KeyboardState {
    var lease: KeyboardLease?
    var status: VoiceStatus?
    var selectionReview: KeyboardSelectionReview?
    var selectionRestoration: KeyboardSelectionRestoration?
    var selectionPending = false
    var pending = false
    var streaming = false
    var standbyLive = false
    var errorKey: String?
}
@MainActor final class KeyboardController {
    var bridge: SharedVoiceBridge?
    let textDocumentProxy: Proxy
    var state = KeyboardState()
    var visible = true, hasFullAccess = true
    var selectionOutput: KeyboardSelectionOutput?
    var selectionTarget: KeyboardSelectionTarget?
    var selectionSessionID: UUID?
    var selectionExpectedCallbacks = Set<SelectionInputChange>()
    var selectionAwaitingSettlement = false
    var polling: Task<Void, Never>?
    var signature: [String?] = []
    init(_ bridge: SharedVoiceBridge, _ proxy: Proxy) { self.bridge = bridge; textDocumentProxy = proxy }
    func documentID() -> UUID? { textDocumentProxy.id }
    func refreshInputTraits() {}
    func validateUndo() {}
    func startFromIntentIfReady() {}
    func keyFeedback() {}
    func voiceBridge() throws -> SharedVoiceBridge { bridge! }
    func poll(lease: KeyboardLease, action: VoiceAction, captureRequestID: UUID?) { preconditionFailure("ordinary poll outside selection check") }
}

@MainActor final class VoiceHost {
    static var shared: VoiceHost!
    let controller: MobileController
    var completed: [UUID] = []
    init(_ controller: MobileController) { self.controller = controller }
    func perform(_ id: UUID) async throws { try await controller.perform(id); completed.append(id) }
}
@MainActor final class StandbyService {
    let controller: MobileController
    var activationID: UUID? = UUID()
    let log = Logger(subsystem: "com.ichendev.utter.local-check", category: "Selection")
    init(_ controller: MobileController) { self.controller = controller }
    func run() async { await serve(generation: activationID!) }
}

enum CheckFailure: Error { case deadline(String) }
@MainActor func until(_ name: String, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(4)
    while !condition() {
        guard Date() < deadline else { throw CheckFailure.deadline(name) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@main struct MobileSelectionLifecycleCheck {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = try SharedVoiceBridge(container: directory)
        let proxy = Proxy(), history = History(), factory = MobileWorkflowFactory()
        let driver = SessionDriver(workflows: factory, history: history, notifications: StateNotifications())
        let app = MobileController(bridge); app.factory = factory; app.execution = driver
        let observation = driver.observe { snapshot in app.projectSelection(snapshot) }
        let host = VoiceHost(app); VoiceHost.shared = host
        let service = StandbyService(app)
        let serving = Task { await service.run() }
        let keyboard = KeyboardController(bridge, proxy)
        var passed: [String] = []
        func verify(_ name: String, _ value: Bool) {
            precondition(value, name); passed.append(name)
            FileHandle.standardError.write(Data((name + "\n").utf8))
        }
        keyboard.refresh()
        let start = UUID()
        verify("selected native Start posts one frozen admission", keyboard.prepare(id: start, action: .start, lease: keyboard.state.lease!))
        try await until("recording") { keyboard.state.status?.phase == .recording }
        let stop = UUID()
        verify("selected native Stop posts into real serial serving loop", keyboard.prepare(id: stop, action: .stop, lease: keyboard.state.lease!))
        try await until("Stop returned and review arrived") { host.completed.contains(stop) && keyboard.state.selectionReview != nil }
        verify("Stop returns before Apply without awaiting whole job", driver.snapshot.phase == .processing && driver.snapshot.isBusy && proxy.inserts == 0)
        verify("review stays in same admitted shared session", driver.snapshot.id == start && factory.jobs.count == 1 && keyboard.state.selectionReview?.sessionID == start)
        keyboard.applySelectionEdit()
        try await until("native Apply and delayed resource drain") { keyboard.selectionAwaitingSettlement && factory.jobs[0].closing }
        verify("native acknowledged Apply retains restore while actual job drains", keyboard.state.selectionRestoration != nil && proxy.inserts == 1 && keyboard.selectionOutput?.edit.phase == .applied)
        try await Task.sleep(for: .milliseconds(450))
        verify("multiple polling ticks cannot reinstall stale review or revoke restore", keyboard.selectionAwaitingSettlement && keyboard.state.selectionReview == nil && keyboard.state.selectionRestoration != nil)
        try await until("Apply terminal") { keyboard.selectionSessionID == nil && keyboard.state.status?.phase == .ready }
        verify("Apply terminal resets waiting flag and keeps confirmed restore", !keyboard.selectionAwaitingSettlement && keyboard.state.selectionRestoration != nil && keyboard.selectionOutput?.edit.phase == .applied)
        verify("real shared driver confirms native keyboard insertion without history", driver.snapshot.deliveryStatus == .inserted && history.writes == 0 && factory.completions[0].text.isEmpty)
        let restoration = keyboard.state.selectionRestoration!
        keyboard.restoreSelectionEdit()
        try await until("Restore terminal") { keyboard.selectionSessionID == nil && factory.completions.count == 2 }
        verify("new same-MobileJob typed restore consumes the native operation", factory.jobs.count == 2 && proxy.before.utf8.elementsEqual(("前 " + proxy.original).utf8) && proxy.inserts == 2)
        if case .restoreSelectionEdit(let operationID) = factory.intents[1].operation { verify("restore intent is bound to actual first native operation", operationID == restoration.operationID) }
        else { preconditionFailure("restore intent") }
        verify("restoration runs without generation and leaves no reusable restore", app.polishService.calls == 1 && keyboard.state.selectionRestoration == nil && keyboard.selectionOutput == nil && !keyboard.selectionAwaitingSettlement)
        verify("selected shared terminal snapshots contain no original or instruction", driver.snapshot.text.isEmpty && driver.snapshot.transcript.isEmpty && driver.snapshot.selectionEditProposal == nil)

        // A second real admission proves Cancel reaches the existing lease watcher and drains the same job.
        proxy.before = "前 "; proxy.selection = proxy.original
        keyboard.refresh()
        let cancelStart = UUID()
        _ = keyboard.prepare(id: cancelStart, action: .start, lease: keyboard.state.lease!)
        try await until("second recording") { keyboard.state.status?.phase == .recording }
        _ = keyboard.prepare(id: UUID(), action: .stop, lease: keyboard.state.lease!)
        try await until("second review") { keyboard.state.selectionReview != nil }
        keyboard.cancelSelectionEdit()
        try await until("Cancel drained") { driver.snapshot.phase == .cancelled }
        verify("Cancel leaves original selection and never writes", proxy.inserts == 2 && proxy.selectedText == proxy.original && keyboard.selectionOutput == nil)
        verify("Cancel removes private bridge payload", !FileManager.default.fileExists(atPath: directory.appendingPathComponent("UtterVoice-v1/selection-review.json").path) && factory.selectionRequest == nil)
        app.polishAvailable = false
        keyboard.refresh()
        let unavailableStart = UUID()
        _ = keyboard.prepare(id: unavailableStart, action: .start, lease: keyboard.state.lease!)
        try await until("unavailable local backend") { app.status.requestID == unavailableStart && app.status.phase == .failed }
        verify("model admission failure stays explicitly private before proposal", app.status.selectionMode == true && app.status.text.isEmpty && factory.jobs.count == 3 && proxy.inserts == 2)
        service.activationID = nil; serving.cancel(); await serving.value
        keyboard.polling?.cancel(); app.watchdog?.cancel()
        driver.removeObserver(observation); await driver.close()
        let data = try JSONSerialization.data(withJSONObject: ["passed": passed.count, "checks": passed,
            "scope": "Actual command/Stop/projection/lease watcher, serial serving and keyboard selection polling/handlers, real shared driver/recipe/bridge/native writer; controlled capture/ASR/model/platform setup/proxy. No microphone or native UI."], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
