import Foundation
import UtterContracts
import UtterProcessing
import UtterKeyboardBridge
@testable import UtterSession

@MainActor protocol UITextDocumentProxy {
    var selectedText: String? { get }
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
}

@MainActor final class Proxy: UITextDocumentProxy {
    var id = UUID(), before = "前 ", after = " 后"
    var original = " \n" + String(repeating: "完整原文", count: 200) + "👨‍👩‍👧‍👦\n "
    var selection: String?
    var hidden = false, inserts = 0, deletes = 0
    init() { selection = original }
    var selectedText: String? { selection }
    var documentContextBeforeInput: String? { hidden ? nil : before }
    var documentContextAfterInput: String? { after }
    func insertText(_ text: String) { inserts += 1; selection = nil; before += text }
    func deleteBackward() { deletes += 1; if !before.isEmpty { before.removeLast() } }
}

@MainActor final class LocalPolisher {
    var raw = "{\"final_text\":\"您好👨‍👩‍👧‍👦\"}"
    var calls = 0, fail = false
    var options: UtterContracts.GenerationOptions?
    func generate(prompt: String, system: String, options: UtterContracts.GenerationOptions, modelID: String) async throws -> String {
        calls += 1; self.options = options
        guard !fail else { throw BridgeError.unavailable }
        return raw
    }
}

@MainActor final class MobileJob {
    let selection: MobileSelectionRequest?
    let language = "zh"
    let dictionary = PersonalDictionarySnapshot(entries: [], editRules: [])
    var selectionOutput: KeyboardSelectionOperation?
    init(_ selection: MobileSelectionRequest) { self.selection = selection }
    func check(_ control: any SessionJobControl) throws {
        try Task.checkCancellation()
        guard control.isCurrent else { throw CancellationError() }
    }
}

enum SelectionInputChange { case text, selectionWill, selectionDid }
@MainActor final class KeyboardController {
    let textDocumentProxy: Proxy
    var selectionOutput: KeyboardSelectionOutput?
    var selectionSessionID: UUID?
    var selectionExpectedCallbacks = Set<SelectionInputChange>()
    init(_ proxy: Proxy) { textDocumentProxy = proxy }
    func documentID() -> UUID? { textDocumentProxy.id }
}

@MainActor final class Scenario {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let proxy = Proxy(), generator = LocalPolisher()
    let bridge: SharedVoiceBridge
    let lease: KeyboardLease
    let session = UUID()
    var projectedSession: UUID?
    let target: KeyboardSelectionTarget
    var control: SessionControl!
    var current = true
    init() throws {
        bridge = try SharedVoiceBridge(container: directory)
        lease = KeyboardLease(generation: UUID(), documentID: proxy.id)
        target = try KeyboardSelectionTarget(documentID: proxy.id, selectedText: proxy.original, contextBefore: proxy.before, contextAfter: proxy.after)
        try bridge.renew(lease)
        try publish(phase: .recording, id: session)
        control = SessionControl(isCurrent: { [unowned self] in self.current }, cancel: { [unowned self] in
            self.current = false; self.control.revoke()
        }, update: { [unowned self] phase, _ in
            try! self.publish(phase: phase == .recording ? .recording : .processing, id: self.projectedSession ?? self.session)
            if let proposal = self.control.selectionEditProposal {
                try! self.bridge.publishSelectionReview(KeyboardSelectionReview(id: proposal.id, sessionID: proposal.sessionID,
                    lease: self.lease, target: self.target, recognizedInstruction: proposal.recognizedInstruction,
                    candidate: proposal.candidate, expiresAt: proposal.expiresAt))
            }
        })
    }
    func publish(phase: VoicePhase, id: UUID) throws {
        var status = VoiceStatus(generation: lease.generation, phase: phase)
        status.selectionMode = true; status.requestID = id; status.leaseID = lease.id; status.documentID = lease.documentID
        try bridge.publish(status)
    }
    func job(_ operation: MobileSelectionOperation? = nil, id: UUID? = nil) -> MobileJob {
        MobileJob(MobileSelectionRequest(sessionID: id ?? session, lease: lease,
            operation: operation ?? .edit(target, modelID: "system"), bridge: bridge, polisher: generator))
    }
    func waitForProposal() async throws -> SelectionEditProposal {
        for _ in 0..<100 {
            if let proposal = control.selectionEditProposal { return proposal }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw BridgeError.unavailable
    }
    func waitForOperation(_ id: UUID) async throws -> KeyboardSelectionOperation {
        for _ in 0..<100 {
            if let value = try bridge.selectionOperation(sessionID: id) { return value }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw BridgeError.unavailable
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@main struct MobileSelectionCheck {
    @MainActor static func main() async throws {
        var passed: [String] = []
        func verify(_ name: String, _ result: Bool) {
            precondition(result, name); passed.append(name)
            FileHandle.standardError.write(Data((name + "\n").utf8))
        }
        let s = try Scenario()
        defer { s.cleanup() }
        let job = s.job()
        let task = Task { try await job.finishSelection("改礼貌一点", control: s.control) }
        let proposal = try await s.waitForProposal()
        verify("full original byte binding and nil desktop PID", proposal.originalSelection.utf8.elementsEqual(s.proxy.original.utf8) && proposal.processIdentifier == nil && proposal.targetID == s.proxy.id)
        verify("actual portable recipe options reach raw generation", s.generator.options?.maxTokens == SelectionEditRecipe.selectionEditOptions(for: s.proxy.original, intent: .custom("改礼貌一点")).maxTokens)
        verify("review has genuine recognized instruction", proposal.recognizedInstruction == "改礼貌一点" && proposal.candidate == "您好👨‍👩‍👧‍👦")
        verify("no native operation or host write before Apply", try s.bridge.selectionOperation(sessionID: s.session) == nil && s.proxy.inserts == 0)
        verify("wrong proposal cannot resume review", !s.control.applySelectionEdit(UUID()))
        verify("one Apply resumes same control", s.control.applySelectionEdit(proposal.id) && !s.control.applySelectionEdit(proposal.id))
        let operation = try await s.waitForOperation(s.session)
        let output = KeyboardSelectionOutput(edit: try KeyboardSelectionEdit(id: proposal.id, target: s.target, candidate: proposal.candidate))
        try s.bridge.takeSelectionOperation(operation)
        let confirmed = try output.apply(proxy: s.proxy, documentID: { s.proxy.id })
        let restoration = KeyboardSelectionRestoration(operationID: operation.id, sessionID: s.session, lease: operation.lease, expiresAt: s.target.expiresAt)
        let ack = KeyboardSelectionAcknowledgement(operation: operation, wrote: output.wroteThisOperation, confirmed: confirmed)
        try s.bridge.acknowledgeSelection(ack, restoration: restoration)
        let completion = try await task.value
        verify("full native readback confirms keyboardInsertion", completion.acceptance.deliveryStatus == .inserted && s.proxy.inserts == 1)
        verify("selected completion has no private text/history/followup", completion.text.isEmpty && completion.transcript.isEmpty && completion.record == nil && completion.historyReplacement == nil && completion.followup == nil)
        if case .preserve = completion.outputMutation { passed.append("selected completion preserves desktop recent output") } else { preconditionFailure() }
        job.clearSelectionPayload()
        verify("settling removes review and delivery payload", try !FileManager.default.fileExists(atPath: s.directory.appendingPathComponent("UtterVoice-v1/selection-review.json").path) && s.bridge.selectionAcknowledgement(for: operation) == nil)
        verify("confirmed restoration metadata survives settlement", try s.bridge.selectionRestoration() == restoration)

        let observer = KeyboardController(s.proxy)
        observer.selectionOutput = output; observer.selectionSessionID = s.session
        observer.selectionExpectedCallbacks = [.text, .selectionWill, .selectionDid]
        verify("one exact owned callback is admitted", observer.observeOwnedSelectionChange(.text))
        verify("duplicate callback cannot conceal later input", !observer.observeOwnedSelectionChange(.text))
        s.proxy.before += "外部修改"
        verify("expected callback rejects changed visible text", !observer.observeOwnedSelectionChange(.selectionDid))
        s.proxy.before = "前 " + proposal.candidate

        let restoreID = UUID()
        s.projectedSession = restoreID
        try s.publish(phase: .processing, id: restoreID)
        let restoreJob = s.job(.restore(restoration), id: restoreID)
        let restoreTask = Task { try await restoreJob.restoreSelection(control: s.control) }
        let restoreOperation = try await s.waitForOperation(restoreID)
        verify("typed restore consumes metadata before native effect", try s.bridge.selectionRestoration() == nil && s.proxy.deletes == 0)
        try s.bridge.takeSelectionOperation(restoreOperation)
        let restored = try output.restore(proxy: s.proxy, documentID: { s.proxy.id })
        try s.bridge.acknowledgeSelection(KeyboardSelectionAcknowledgement(operation: restoreOperation, wrote: output.wroteThisOperation, confirmed: restored))
        let restoredCompletion = try await restoreTask.value
        verify("typed restore reads back full original once without generation", restoredCompletion.acceptance.deliveryStatus == .inserted && s.proxy.before.utf8.elementsEqual(("前 " + s.proxy.original).utf8) && s.generator.calls == 1)
        do { _ = try output.restore(proxy: s.proxy, documentID: { s.proxy.id }); preconditionFailure("restore replay") } catch { passed.append("restore replay is rejected") }
        restoreJob.clearSelectionPayload()

        for (name, raw, fail) in [("structured metadata", "{\"final_text\":\"\",\"text\":\"metadata\"}", false), ("action-only", "{\"action\":\"delete_selection\",\"text\":\"delete\"}", false), ("generation failure", "", true)] {
            let failed = try Scenario(); defer { failed.cleanup() }
            failed.generator.raw = raw; failed.generator.fail = fail
            let failedJob = failed.job()
            do { _ = try await failedJob.finishSelection("改礼貌一点", control: failed.control); preconditionFailure(name) }
            catch { verify(name + " has no review/effect/fallback", try failed.control.selectionEditProposal == nil && failed.proxy.inserts == 0 && failed.bridge.selectionOperation(sessionID: failed.session) == nil) }
            failedJob.clearSelectionPayload()
        }
        let cancelled = try Scenario(); defer { cancelled.cleanup() }
        let cancelledJob = cancelled.job()
        let cancelledTask = Task { try await cancelledJob.finishSelection("改礼貌一点", control: cancelled.control) }
        _ = try await cancelled.waitForProposal()
        cancelled.control.cancel()
        do { _ = try await cancelledTask.value; preconditionFailure("cancel") } catch { verify("Cancel preserves original with no native operation", cancelled.proxy.inserts == 0) }
        cancelledJob.clearSelectionPayload()
        verify("Cancel clears private review file", !FileManager.default.fileExists(atPath: cancelled.directory.appendingPathComponent("UtterVoice-v1/selection-review.json").path))
        let timeout = try Scenario(); defer { timeout.cleanup() }
        let timeoutJob = timeout.job()
        let timeoutTask = Task { try await timeoutJob.finishSelection("改礼貌一点", control: timeout.control) }
        let timeoutProposal = try await timeout.waitForProposal()
        _ = timeout.control.applySelectionEdit(timeoutProposal.id)
        let timedOperation = try await timeout.waitForOperation(timeout.session)
        try timeout.bridge.takeSelectionOperation(timedOperation)
        let missing = try await timeoutTask.value
        verify("missing native acknowledgement remains uncertain", missing.acceptance.deliveryStatus == .uncertain && !missing.accepted)
        timeoutJob.clearSelectionPayload()
        do { try timeout.bridge.acknowledgeSelection(KeyboardSelectionAcknowledgement(operation: timedOperation, wrote: true, confirmed: true)); preconditionFailure("late ack") }
        catch { passed.append("late acknowledgement cannot restore authority") }
        let data = try JSONSerialization.data(withJSONObject: ["passed": passed.count, "checks": passed, "scope": "Real shared control/recipe and bridge + actual mobile selection/native writer methods; controlled model, MobileJob shell and UIKit proxy. No physical host or microphone."], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
