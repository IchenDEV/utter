import Foundation

/// What macOS itself does with a remote key when nothing is mapped, as measured on the RC003.
package enum NativeKeyEvent: Equatable, Sendable {
    /// A keyboard event; `flags` are the CGEvent flag bits macOS adds for this key (fn, numeric pad).
    case key(code: UInt16, flags: UInt64)
    /// A system-defined media key (`NX_KEYTYPE_*`).
    case media(UInt32)
    /// macOS produces no event at all.
    case none
}

/// The RC003's keys that can be mapped. The voice key is not here: it is fixed. The power key is
/// not here either: it was deliberately not measured, so its usage is unknown.
package enum RemoteButton: String, CaseIterable, Codable, Sendable {
    case up, down, left, right, ok, back, home, menu, tv, volumeUp, volumeDown

    private static let keyboardPage: UInt64 = 7
    private static let secondaryFn: UInt64 = 0x80_0000
    private static let numericPad: UInt64 = 0x20_0000

    /// HID keyboard-page usage the remote reports for this key.
    package var usage: Int {
        switch self {
        case .up: 82
        case .down: 81
        case .left: 80
        case .right: 79
        case .ok: 40
        case .back: 241
        case .home: 74
        case .menu: 101
        case .tv: 53
        case .volumeUp: 128
        case .volumeDown: 129
        }
    }

    /// The source as `UserKeyMapping` encodes it: usage page in the high 32 bits, usage in the low.
    package var hidSource: UInt64 { (Self.keyboardPage << 32) | UInt64(usage) }

    package var nativeEvent: NativeKeyEvent {
        switch self {
        case .up: .key(code: 126, flags: Self.secondaryFn | Self.numericPad)
        case .down: .key(code: 125, flags: Self.secondaryFn | Self.numericPad)
        case .left: .key(code: 123, flags: Self.secondaryFn | Self.numericPad)
        case .right: .key(code: 124, flags: Self.secondaryFn | Self.numericPad)
        case .ok: .key(code: 36, flags: 0)
        case .back: .none
        case .home: .key(code: 115, flags: Self.secondaryFn)
        case .menu: .key(code: 110, flags: 0)
        case .tv: .key(code: 10, flags: 0)
        case .volumeUp: .media(0)
        case .volumeDown: .media(1)
        }
    }

    package init?(usagePage: Int, usage: Int) {
        guard UInt64(usagePage) == Self.keyboardPage,
              let match = Self.allCases.first(where: { $0.usage == usage }) else { return nil }
        self = match
    }
}
