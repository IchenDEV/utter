import AppKit
import Carbon.HIToolbox

@MainActor
enum NativeDeliveryKeys {
    static var isSecureInput: Bool { IsSecureEventInputEnabled() }

    static func prepare(deleting: Bool) -> (() -> Bool)? {
        guard !isSecureInput,
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(deleting ? kVK_Delete : kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(deleting ? kVK_Delete : kVK_ANSI_V), keyDown: false) else { return nil }
        let flags: CGEventFlags = deleting ? [] : .maskCommand
        down.flags = flags
        up.flags = flags
        return {
            guard !isSecureInput else { return false }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            return true
        }
    }
}
