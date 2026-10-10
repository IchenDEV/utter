import AppKit
import ApplicationServices
import Foundation
import UtterContracts

@MainActor
final class AXCorrectionObservation: CorrectionObservationSource {
    private let processIdentifier: pid_t
    private let element: AXUIElement
    private let locator: CorrectionCaptureRegionLocator
    private let context: InputContext
    private var observer: AXObserver?
    private var callback: (() -> Void)?
    private var observationID: UUID?

    init(processIdentifier: pid_t, element: AXUIElement,
         locator: CorrectionCaptureRegionLocator, context: InputContext) {
        self.processIdentifier = processIdentifier
        self.element = element
        self.locator = locator
        self.context = context
    }

    var isEligible: Bool {
        CorrectionCapturePrivacyPolicy.isEligible(
            bundleIdentifier: context.bundleIdentifier, appName: context.appName, element: element
        )
    }

    var isFocused: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
            && CorrectionCaptureAX.isFocused(element, pid: processIdentifier)
    }

    func readEditedText() -> String? {
        guard let text = CorrectionCaptureAX.stringValue(of: element, attribute: kAXValueAttribute as CFString) else { return nil }
        return locator.editedText(in: text)
    }

    func observe(_ callback: @escaping () -> Void) -> UUID? {
        guard observer == nil else { return nil }
        var created: AXObserver?
        guard AXObserverCreate(processIdentifier, correctionObservationCallback, &created) == .success,
              let created else { return nil }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(created, element, kAXValueChangedNotification as CFString, pointer) == .success else { return nil }
        observer = created
        self.callback = callback
        let id = UUID()
        observationID = id
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        return id
    }

    func removeObserver(_ id: UUID) {
        guard observationID == id, let observer else { return }
        AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        observationID = nil
        callback = nil
    }

    fileprivate func valueChanged(_ element: AXUIElement) {
        guard CFEqual(self.element, element) else { return }
        callback?()
    }
}

private func correctionObservationCallback(_: AXObserver, element: AXUIElement, _: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    MainActor.assumeIsolated {
        let source = Unmanaged<AXCorrectionObservation>.fromOpaque(refcon).takeUnretainedValue()
        source.valueChanged(element)
    }
}

private enum CorrectionCaptureAX {
    static func stringValue(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    static func isFocused(_ element: AXUIElement, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return false
        }
        return CFEqual(element, value)
    }
}


extension CorrectionCapturePrivacyPolicy {
    package static func isEligible(
        bundleIdentifier: String?,
        appName: String?,
        element: AXUIElement
    ) -> Bool {
        let appText = [bundleIdentifier, appName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        let fieldText = [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXIdentifierAttribute,
        ].compactMap {
            CorrectionCaptureAX.stringValue(of: element, attribute: $0 as CFString)?.lowercased()
        }.joined(separator: " ")
        return !isBlocked(appText: appText, fieldText: fieldText)
    }

}
