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
    private let pasteboard: NativeDeliveryPasteboard

    init(log: Log, isCurrent: @escaping () -> Bool, pasteboard: NSPasteboard = .general) {
        self.log = log
        self.isCurrent = isCurrent
        self.pasteboard = NativeDeliveryPasteboard(pasteboard)
    }

    func deliver(_ request: DeliveryRequest, canCommit: @escaping () -> Bool,
                 markCommitted: @escaping (DeliveryEffect) -> Bool) async -> DeliveryCompletion {
        let text: String
        let target: (any OutputTargetLease)?
        let anchor: (any OutputAnchor)?
        let requiresSelection: Bool
        switch request.command {
        case .clipboard(let value):
            return ClipboardPasteTransaction.copy(value, pasteboard: pasteboard, canCommit: canCommit, mark: markCommitted)
        case .insert(let value): text = value; target = request.target; anchor = nil; requiresSelection = false
        case .replaceSelection(let value): text = value; target = request.target; anchor = nil; requiresSelection = true
        case .deleteSelection: text = ""; target = request.target; anchor = nil; requiresSelection = true
        case .replaceAnchor(let value, let previous): text = value; target = previous.target; anchor = previous; requiresSelection = false
        case .undoAnchor(let previous): text = ""; target = previous.target; anchor = previous; requiresSelection = false
        }
        guard canCommit(), let target,
              let destination = NativeDeliveryTarget(lease: target, anchor: anchor, requiresSelection: requiresSelection) else {
            return DeliveryCompletion(disposition: .notCommitted, reason: L("delivery.target_changed"))
        }
        var result = await TextDeliveryTransaction.deliver(text, target: destination, pasteboard: pasteboard,
            allowsClipboardPaste: request.allowsClipboardPaste, isSecureInput: { NativeDeliveryKeys.isSecureInput },
            prepareKeys: NativeDeliveryKeys.prepare, canCommit: canCommit, mark: markCommitted)
        if result.disposition == .accepted, result.confirmation == .targetValue {
            result.anchor = destination.insertionAnchor(text, isCurrent: isCurrent)
        }
        log.info("Delivery completed: \(result.disposition), confirmation: \(result.confirmation.rawValue)")
        return result
    }
}
