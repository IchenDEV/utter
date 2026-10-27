import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import UtterContracts
import UtterRuntime

@MainActor
final class NativeTargetLease: OutputTargetLease {
    let id: UUID
    let processIdentifier: Int32
    let context: InputContext
    private let state: AXTargetState?
    private let documentFingerprint: SHA256.Digest?
    private let focusedElement: AXUIElement?
    private let isOwnerCurrent: () -> Bool

    init(id: UUID = UUID(), processIdentifier: Int32, state: AXTargetState?, context: InputContext,
         isCurrent: @escaping () -> Bool) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.state = state
        documentFingerprint = state.flatMap { AXTargetState.value(of: $0.element) }.map { SHA256.hash(data: Data($0.utf8)) }
        focusedElement = state?.element ?? AXTargetState.focusedIdentity()?.1
        self.context = context
        isOwnerCurrent = isCurrent
    }

    var selectedText: String? { state?.selected ?? context.selectedText }

    var isValid: Bool { isOwnerCurrent() && NSRunningApplication(processIdentifier: processIdentifier)?.isTerminated == false }

    var isCurrent: Bool {
        guard !NativeDeliveryKeys.isSecureInput, isValid, let focusedElement, let (pid, element) = AXTargetState.focusedIdentity(),
              pid == processIdentifier, CFEqual(focusedElement, element) else { return false }
        guard let state else { return true }
        guard let current = AXTargetState.capture() else { return false }
        let fingerprint = AXTargetState.value(of: current.element).map { SHA256.hash(data: Data($0.utf8)) }
        return state.matches(current) && documentFingerprint == fingerprint
    }
}

@MainActor
extension MacPlugins {
    package static func target() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "mac.target", provides: [MacServices.target.reference])) { context, _ in
            try context.provide(MacServices.target, value: NativeTargetCapture(isCurrent: { context.isReady }))
        }
    }
}

@MainActor
private final class NativeTargetCapture: TargetCaptureService {
    private let isCurrent: () -> Bool
    init(isCurrent: @escaping () -> Bool) { self.isCurrent = isCurrent }

    func capture(_ request: TargetCaptureRequest) throws -> any OutputTargetLease {
        guard isCurrent(), !Task.isCancelled, !NativeDeliveryKeys.isSecureInput, let app = NSWorkspace.shared.frontmostApplication else { throw DeliveryError.invalidTarget }
        let state = AXTargetState.capture()
        guard !NativeDeliveryKeys.isSecureInput else { throw DeliveryError.invalidTarget }
        let context = InputContext.capture(targetApp: app, screenContext: request.screenContext,
            outputMode: request.outputMode, inputLanguage: request.inputLanguage, source: request.source)
        guard !NativeDeliveryKeys.isSecureInput else { throw DeliveryError.invalidTarget }
        return NativeTargetLease(processIdentifier: app.processIdentifier, state: state, context: context, isCurrent: isCurrent)
    }
}
