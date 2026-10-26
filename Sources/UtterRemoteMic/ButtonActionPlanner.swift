import Foundation
import UtterContracts

/// One low-level step of an action. A poster turns each into a real event or call.
enum SyntheticInput: Equatable, Sendable {
    /// `isModifier`: a modifier key press or release, which macOS reports as a flags-changed event.
    case key(code: UInt16, down: Bool, flags: UInt64, isModifier: Bool)
    /// A system-defined media key (`NX_KEYTYPE_*`).
    case media(key: UInt32, down: Bool)
    case openApp(bundleID: String)

    /// Anything that would be typed or shortcut-handled by whatever has the keyboard.
    var isKeyboard: Bool {
        if case .openApp = self { return false }
        return true
    }
}

struct KeyboardShortcut: Equatable, Sendable {
    var keyCode: UInt16
    var flags: UInt64
}

/// `CGEventFlags` bits.
enum EventFlag {
    static let shift: UInt64 = 0x2_0000
    static let control: UInt64 = 0x4_0000
    static let option: UInt64 = 0x8_0000
    static let command: UInt64 = 0x10_0000
    static let secondaryFn: UInt64 = 0x80_0000
    static let modifierMask = shift | control | option | command
    static let shortcutMask = modifierMask | secondaryFn
}

/// Pure: how each action becomes events. Measured on the RC003's Mac (macOS 27): a chord that only
/// sets flags on the key event does nothing for the app switcher; the modifier keys must be pressed
/// and released as their own events. Show Desktop reacts to F11 with the fn flag.
enum ButtonActionPlanner {
    private static let modifierKeys: [(flag: UInt64, code: UInt16)] = [
        (EventFlag.control, 59), (EventFlag.option, 58), (EventFlag.shift, 56), (EventFlag.command, 55),
    ]
    private static let tab: UInt16 = 48

    static let standardShowDesktop = KeyboardShortcut(keyCode: 103, flags: EventFlag.secondaryFn)

    /// `showDesktop` is `nil` when the user has turned that shortcut off.
    static func inputs(
        for action: ButtonAction, button: RemoteButton, showDesktop: KeyboardShortcut?
    ) -> [SyntheticInput] {
        switch action {
        case .native: native(button.nativeEvent)
        case .key(let chord): chordInputs(code: chord.keyCode, flags: flags(of: chord.modifiers))
        case .system(let key): [.media(key: mediaKey(key), down: true), .media(key: mediaKey(key), down: false)]
        case .showDesktop: showDesktop.map { chordInputs(code: $0.keyCode, flags: $0.flags) } ?? []
        case .appSwitcher: chordInputs(code: tab, flags: EventFlag.command)
        case .openApp(let bundleID): [.openApp(bundleID: bundleID)]
        }
    }

    /// The press the key would have produced if it had not been silenced.
    private static func native(_ event: NativeKeyEvent) -> [SyntheticInput] {
        switch event {
        case .key(let code, let flags): chordInputs(code: code, flags: flags)
        case .media(let key): [.media(key: key, down: true), .media(key: key, down: false)]
        case .none: []
        }
    }

    /// Modifiers down in a fixed order, the key down and up with the full flags, modifiers up in reverse.
    /// Flags outside the four modifiers (fn, numeric pad) ride on the key events only.
    static func chordInputs(code: UInt16, flags: UInt64) -> [SyntheticInput] {
        let extra = flags & ~EventFlag.modifierMask
        let held = modifierKeys.filter { flags & $0.flag != 0 }
        var steps: [SyntheticInput] = []
        var current = extra
        for modifier in held {
            current |= modifier.flag
            steps.append(.key(code: modifier.code, down: true, flags: current, isModifier: true))
        }
        steps.append(.key(code: code, down: true, flags: current, isModifier: false))
        steps.append(.key(code: code, down: false, flags: current, isModifier: false))
        for modifier in held.reversed() {
            current &= ~modifier.flag
            steps.append(.key(code: modifier.code, down: false, flags: current, isModifier: true))
        }
        return steps
    }

    static func flags(of modifiers: KeyChord.Modifiers) -> UInt64 {
        var result: UInt64 = 0
        if modifiers.contains(.command) { result |= EventFlag.command }
        if modifiers.contains(.option) { result |= EventFlag.option }
        if modifiers.contains(.control) { result |= EventFlag.control }
        if modifiers.contains(.shift) { result |= EventFlag.shift }
        return result
    }

    static func mediaKey(_ key: SystemKey) -> UInt32 {
        switch key {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    /// The user's Show Desktop shortcut from `com.apple.symbolichotkeys` (hotkey 36). Absent means the
    /// system default, which is not written to the file until the user changes it. `nil`: turned off or
    /// no key assigned.
    static func resolveShowDesktop(symbolicHotKeys: [String: Any]?) -> KeyboardShortcut? {
        guard let entry = symbolicHotKeys?["36"] as? [String: Any] else { return standardShowDesktop }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = (value["parameters"] as? [NSNumber])?.map(\.intValue), parameters.count == 3 else {
            return standardShowDesktop
        }
        guard (0 ..< 65_535).contains(parameters[1]) else { return nil }
        return KeyboardShortcut(
            keyCode: UInt16(parameters[1]), flags: UInt64(max(0, parameters[2])) & EventFlag.shortcutMask
        )
    }
}
