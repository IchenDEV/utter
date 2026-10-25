import AppKit
import Carbon.HIToolbox

/// Posts synthetic input at the HID event tap, where the system's own shortcuts see it.
@MainActor
final class SystemInputPoster: SyntheticInputPosting {
    private let source = CGEventSource(stateID: .combinedSessionState)

    static var isSecureInput: Bool { IsSecureEventInputEnabled() }

    /// The user's `com.apple.symbolichotkeys` entries; `nil` when the preference does not exist.
    static func symbolicHotKeys() -> [String: Any]? {
        CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
            as? [String: Any]
    }

    func post(_ input: SyntheticInput) -> Bool {
        switch input {
        case .key(let code, let down, let flags, let isModifier):
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else {
                return false
            }
            if isModifier { event.type = .flagsChanged }
            event.flags = CGEventFlags(rawValue: flags)
            event.post(tap: .cghidEventTap)
            return true
        case .media(let key, let down):
            let state = down ? 0xA00 : 0xB00
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (Int(key) << 16) | state, data2: -1
            )?.cgEvent else { return false }
            event.post(tap: .cghidEventTap)
            return true
        case .openApp(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
    }
}
