import AppKit
import UtterContracts

/// Localization keys and display text for the remote button mapping page. Pure so the mapping is
/// unit-testable without a view.
package enum RemoteButtonMappingText {
    package enum PermissionAction: Equatable {
        case allow
        case openSettings
    }

    package static func stateKey(_ state: RemoteButtonMappingState) -> String {
        switch state {
        case .off: return "remote_buttons.state.off"
        case .waitingForRemote: return "remote_buttons.state.waiting"
        case .needsPermission: return "remote_buttons.state.needs_permission"
        case .needsRestart: return "remote_buttons.state.needs_restart"
        case .active: return "remote_buttons.state.active"
        case .conflict: return "remote_buttons.state.conflict"
        case .failed: return "remote_buttons.state.failed"
        }
    }

    /// A longer explanation, only for the states the user can act on.
    package static func detailKey(_ state: RemoteButtonMappingState) -> String? {
        switch state {
        case .needsPermission(let canAsk): return canAsk ? "remote_buttons.detail.ask" : "remote_buttons.detail.denied"
        case .needsRestart: return "remote_buttons.detail.restart"
        case .conflict: return "remote_buttons.detail.conflict"
        case .failed: return "remote_buttons.detail.failed"
        case .off, .waitingForRemote, .active: return nil
        }
    }

    package static func permissionAction(_ state: RemoteButtonMappingState) -> PermissionAction? {
        guard case .needsPermission(let canAsk) = state else { return nil }
        return canAsk ? .allow : .openSettings
    }

    package static func needsAttention(_ state: RemoteButtonMappingState) -> Bool { detailKey(state) != nil }

    package static var inputMonitoringSettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    }

    package static func buttonKey(_ button: RemoteButton) -> String { "remote_buttons.button.\(button.rawValue)" }
    package static func triggerKey(_ trigger: ButtonTrigger) -> String { "remote_buttons.trigger.\(trigger.rawValue)" }
    package static func systemKey(_ key: SystemKey) -> String { "remote_buttons.system.\(key.rawValue)" }

    /// What a grid cell shows. `appName` resolves a bundle identifier to a name; nil means not installed.
    package static func summary(of action: ButtonAction, appName: (String) -> String?) -> String {
        switch action {
        case .native: return L("remote_buttons.action.native")
        case .key(let chord): return KeyChordText.describe(chord)
        case .system(let key): return L(systemKey(key))
        case .showDesktop: return L("remote_buttons.action.show_desktop")
        case .appSwitcher: return L("remote_buttons.action.app_switcher")
        case .openApp(let id): return appName(id) ?? L("remote_buttons.action.app_missing")
        }
    }

    @MainActor
    package static func installedAppName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Names a key chord the way macOS menus do: modifiers in control, option, shift, command order.
package enum KeyChordText {
    package static func describe(_ chord: KeyChord) -> String {
        var text = ""
        if chord.modifiers.contains(.control) { text += "⌃" }
        if chord.modifiers.contains(.option) { text += "⌥" }
        if chord.modifiers.contains(.shift) { text += "⇧" }
        if chord.modifiers.contains(.command) { text += "⌘" }
        return text + keyName(chord.keyCode)
    }

    package static func chord(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> KeyChord {
        var modifiers: KeyChord.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return KeyChord(keyCode: keyCode, modifiers: modifiers)
    }

    package static func keyName(_ code: UInt16) -> String {
        names[code] ?? "Key \(code)"
    }

    private static let names: [UInt16: String] = {
        let letters: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
            13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
            40: "K", 45: "N", 46: "M",
        ]
        let symbols: [UInt16: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        ]
        let named: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
            109: "F10", 103: "F11", 111: "F12",
        ]
        return letters.merging(symbols) { a, _ in a }.merging(named) { a, _ in a }
    }()
}
