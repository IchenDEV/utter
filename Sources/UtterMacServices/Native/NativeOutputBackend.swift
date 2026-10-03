import AppKit
import Foundation
import UtterContracts
import UtterRuntime

@MainActor
extension MacPlugins {
    package static func output() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "mac.output", requires: [IntegrationServices.diagnostics.required, MacServices.target.optional],
            provides: [MacServices.output.reference]
        )) { context, _ in
            let backend = NativeOutputBackend(log: Log(service: try context.require(IntegrationServices.diagnostics)),
                isCurrent: { context.isReady })
            let service = ScopedOutputService(isCurrent: { context.isReady }, execute: backend.deliver)
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onDispose { await service.close() }
            try context.provide(MacServices.output, value: service)
        }
    }
}

@MainActor
final class NativeOutputBackend {
    private let log: Log
    private let isCurrent: () -> Bool
    private let pasteboard: NSPasteboard

    init(log: Log, isCurrent: @escaping () -> Bool, pasteboard: NSPasteboard = .general) {
        self.log = log
        self.isCurrent = isCurrent
        self.pasteboard = pasteboard
    }

    func deliver(_ request: DeliveryRequest, canCommit: @escaping () -> Bool,
                 markCommitted: @escaping (DeliveryEffect) -> Bool) async -> DeliveryCompletion {
        if case let .clipboard(text) = request.command {
            guard canCommit(), markCommitted(.clipboard) else { return DeliveryCompletion(disposition: .notCommitted) }
            pasteboard.clearContents()
            let copied = pasteboard.setString(text, forType: .string)
            return DeliveryCompletion(disposition: copied ? .accepted : .uncertain)
        }
        let target: (any OutputTargetLease)?
        let replacement: (any OutputAnchor)?
        switch request.command {
        case let .replaceAnchor(_, anchor), let .undoAnchor(anchor): target = anchor.target; replacement = anchor
        default: target = request.target; replacement = nil
        }
        guard canCommit(), let target, target.isCurrent,
              let app = NSRunningApplication(processIdentifier: target.processIdentifier), !app.isTerminated,
              replacement?.isCurrent ?? true else { return DeliveryCompletion(disposition: .notCommitted, reason: L("pipeline.replacement_reason_text_changed")) }
        let initialState = AXTargetState.capture()
        var preparedSelection: NSRange?
        var effectWasCommitted = false
        let worker = TextInserter(log: log)
        worker.canCommit = {
            guard canCommit(), target.isValid else { return false }
            guard let preparedSelection else { return target.isCurrent }
            guard let initialState, let current = AXTargetState.capture(),
                  initialState.matches(current, selection: preparedSelection),
                  let replacement, let document = AXTargetState.value(of: current.element) else { return false }
            let value = document as NSString
            return NSMaxRange(preparedSelection) <= value.length && value.substring(with: preparedSelection) == replacement.text
        }
        worker.commitEffect = { effect in
            guard markCommitted(effect) else { return false }
            effectWasCommitted = true
            return true
        }
        worker.selectionPrepared = { preparedSelection = replacement?.range }
        if let replacement, let initialState {
            worker.recentInsertionAnchor = RecentInsertionAnchor(processIdentifier: target.processIdentifier,
                element: initialState.element, range: replacement.range, text: replacement.text)
        }
        defer {
            if !effectWasCommitted, let preparedSelection, let initialState, let current = AXTargetState.capture(),
               initialState.matches(current, selection: preparedSelection) { initialState.restoreSelection() }
        }
        let result: InsertResult
        switch request.command {
        case let .insert(text): result = await worker.insert(text: text, targetApp: app)
        case let .replaceSelection(text): result = await worker.replaceSelectedText(text: text, targetApp: app)
        case .deleteSelection: result = await worker.deleteSelectedText(targetApp: app)
        case let .replaceAnchor(text, anchor): result = await worker.replaceRecentInsertion(text: text, previouslyInserted: anchor.text, targetApp: app)
        case let .undoAnchor(anchor): result = await worker.undoRecentInsertion(previouslyInserted: anchor.text, targetApp: app)
        case .clipboard: return DeliveryCompletion(disposition: .notCommitted)
        }
        switch result {
        case .success:
            var anchor: (any OutputAnchor)?
            if let insertion = worker.recentInsertionAnchor, let state = AXTargetState.capture() {
                anchor = NativeOutputAnchor(target: target, anchor: insertion, state: state, isCurrent: isCurrent)
            }
            return DeliveryCompletion(disposition: .accepted, anchor: anchor)
        case let .probablyFailed(reason): return DeliveryCompletion(disposition: .notCommitted, reason: reason)
        }
    }
}
