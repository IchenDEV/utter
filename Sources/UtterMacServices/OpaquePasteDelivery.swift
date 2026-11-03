import Foundation
import UtterContracts

/// A lease captured while the frontmost app exposed no focused element: its content cannot be read, so the only
/// thing that can reach it is a single paste whose result nobody can verify.
@MainActor
protocol OpaqueTargetLease: OutputTargetLease {
    var capturedWithoutFocus: Bool { get }
}

struct OpaqueDeliveryEnvironment {
    var isAccessibilityTrusted: () -> Bool
    var isSecureInput: () -> Bool
    var frontmostProcessIdentifier: () -> Int32?
    var hasFocusedElement: () -> Bool
    var prepareKeys: (_ deleting: Bool) -> (() -> Bool)?
}

enum OpaqueRoute: Equatable {
    case notOpaque
    /// Compatibility mode is on: paste once.
    case paste
    /// The app cannot be written to directly and compatibility mode is off.
    case refuse
}

@MainActor
enum OpaquePasteDelivery {
    /// Only an insertion into the app that was frontmost at capture, which still has no focused element, qualifies.
    /// Accessibility must be trusted so that "no focused element" describes the app and not a missing permission.
    static func route(for request: DeliveryRequest, lease: any OutputTargetLease,
                      environment: OpaqueDeliveryEnvironment) -> OpaqueRoute {
        guard case .insert = request.command, isOpaque(lease, environment) else { return .notOpaque }
        return request.allowsOpaquePaste ? .paste : .refuse
    }

    static func isOpaque(_ lease: any OutputTargetLease, _ environment: OpaqueDeliveryEnvironment) -> Bool {
        guard let lease = lease as? any OpaqueTargetLease, lease.capturedWithoutFocus,
              environment.isAccessibilityTrusted(),
              environment.frontmostProcessIdentifier() == lease.processIdentifier,
              !environment.hasFocusedElement() else { return false }
        return true
    }

    static func deliver(_ text: String, lease: any OutputTargetLease, pasteboard: any DeliveryPasteboard,
                        environment: OpaqueDeliveryEnvironment, canCommit: () -> Bool,
                        mark: (DeliveryEffect) -> Bool) async -> DeliveryCompletion {
        func mayWrite() -> Bool {
            !environment.isSecureInput() && canCommit() && lease.isValid && isOpaque(lease, environment)
        }
        func finish(_ completion: DeliveryCompletion, path: DeliveryPath) -> DeliveryCompletion {
            var completion = completion
            completion.path = path
            completion.target = .opaque
            if completion.disposition == .uncertain { completion.reason = L("delivery.unconfirmed") }
            return completion
        }
        guard !text.isEmpty, mayWrite() else {
            return finish(DeliveryCompletion(disposition: .notCommitted, reason: L("delivery.target_changed")), path: .compatPaste)
        }
        guard let post = environment.prepareKeys(false) else {
            return finish(ClipboardPasteTransaction.copy(text, pasteboard: pasteboard, canCommit: mayWrite, mark: mark),
                          path: .clipboardOnly)
        }
        let result = await ClipboardPasteTransaction.pasteUnobserved(text, pasteboard: pasteboard,
            canCommit: mayWrite, mark: mark, postPaste: post)
        return finish(result, path: .compatPaste)
    }
}
