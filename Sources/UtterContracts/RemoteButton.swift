import Foundation

/// The RC003's keys that can be mapped. The voice key is not here: it is fixed. The power key is
/// not here either: it was deliberately not measured, so its usage is unknown.
package enum RemoteButton: String, CaseIterable, Codable, Sendable {
    case up, down, left, right, ok, back, home, menu, tv, volumeUp, volumeDown

    private static let keyboardPage: UInt64 = 7

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

    package init?(usagePage: Int, usage: Int) {
        guard UInt64(usagePage) == Self.keyboardPage,
              let match = Self.allCases.first(where: { $0.usage == usage }) else { return nil }
        self = match
    }
}
