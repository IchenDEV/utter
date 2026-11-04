import AppKit
import ApplicationServices

extension OpaqueDeliveryEnvironment {
    @MainActor
    static var native: OpaqueDeliveryEnvironment {
        OpaqueDeliveryEnvironment(
            isAccessibilityTrusted: { AXIsProcessTrusted() },
            isSecureInput: { NativeDeliveryKeys.isSecureInput },
            frontmostProcessIdentifier: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            hasFocusedElement: { AXTargetState.focusedIdentity() != nil },
            prepareKeys: NativeDeliveryKeys.prepare)
    }
}
