import Foundation
import UtterContracts

/// What macOS itself does with a remote key when nothing is mapped, as measured on the RC003.
package enum NativeKeyEvent: Equatable, Sendable {
    /// A keyboard event; `flags` are the CGEvent flag bits macOS adds for this key (fn, numeric pad).
    case key(code: UInt16, flags: UInt64)
    /// A system-defined media key (`NX_KEYTYPE_*`).
    case media(UInt32)
    /// macOS produces no event at all.
    case none
}

private enum Flags {
    static let secondaryFn: UInt64 = 0x80_0000
    static let numericPad: UInt64 = 0x20_0000
}

extension RemoteButton {
    package var nativeEvent: NativeKeyEvent {
        switch self {
        case .up: .key(code: 126, flags: Flags.secondaryFn | Flags.numericPad)
        case .down: .key(code: 125, flags: Flags.secondaryFn | Flags.numericPad)
        case .left: .key(code: 123, flags: Flags.secondaryFn | Flags.numericPad)
        case .right: .key(code: 124, flags: Flags.secondaryFn | Flags.numericPad)
        case .ok: .key(code: 36, flags: 0)
        case .back: .none
        case .home: .key(code: 115, flags: Flags.secondaryFn)
        case .menu: .key(code: 110, flags: 0)
        case .tv: .key(code: 10, flags: 0)
        case .volumeUp: .media(0)
        case .volumeDown: .media(1)
        }
    }
}
