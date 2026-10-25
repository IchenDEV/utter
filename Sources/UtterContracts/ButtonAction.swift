import Foundation

package enum ButtonTrigger: String, CaseIterable, Codable, Sendable {
    case single, double, long
}

package enum SystemKey: String, CaseIterable, Codable, Sendable {
    case volumeUp, volumeDown, mute, playPause, previous, next
}

/// A key with modifiers, by macOS virtual key code.
package struct KeyChord: Equatable, Sendable {
    package struct Modifiers: OptionSet, Equatable, Sendable {
        package let rawValue: UInt
        package init(rawValue: UInt) { self.rawValue = rawValue }
        package static let command = Modifiers(rawValue: 1)
        package static let option = Modifiers(rawValue: 2)
        package static let control = Modifiers(rawValue: 4)
        package static let shift = Modifiers(rawValue: 8)
    }

    package var keyCode: UInt16
    package var modifiers: Modifiers

    package init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// What a trigger does. `native` means the key keeps its own behavior. There is deliberately no
/// shell, script or URL action.
package enum ButtonAction: Equatable, Sendable {
    case native
    case key(KeyChord)
    case system(SystemKey)
    case showDesktop
    case appSwitcher
    case openApp(bundleID: String)
}

extension ButtonAction: Codable {
    private struct Wire: Codable {
        var type: String
        var keyCode: UInt16?
        var modifiers: UInt?
        var system: String?
        var bundleID: String?
    }

    /// Anything unreadable or unknown, including actions written by a newer version, decodes to
    /// `native`, so a stored profile can never crash the app or invent an action.
    package init(from decoder: Decoder) throws {
        guard let wire = try? Wire(from: decoder) else {
            self = .native
            return
        }
        switch wire.type {
        case "key":
            guard let code = wire.keyCode else { self = .native; return }
            self = .key(KeyChord(keyCode: code, modifiers: .init(rawValue: wire.modifiers ?? 0)))
        case "system":
            self = wire.system.flatMap(SystemKey.init(rawValue:)).map(ButtonAction.system) ?? .native
        case "showDesktop": self = .showDesktop
        case "appSwitcher": self = .appSwitcher
        case "openApp":
            self = wire.bundleID.flatMap { $0.isEmpty ? nil : $0 }.map { ButtonAction.openApp(bundleID: $0) } ?? .native
        default: self = .native
        }
    }

    package func encode(to encoder: Encoder) throws {
        let wire: Wire
        switch self {
        case .native: wire = Wire(type: "native")
        case .key(let chord): wire = Wire(type: "key", keyCode: chord.keyCode, modifiers: chord.modifiers.rawValue)
        case .system(let key): wire = Wire(type: "system", system: key.rawValue)
        case .showDesktop: wire = Wire(type: "showDesktop")
        case .appSwitcher: wire = Wire(type: "appSwitcher")
        case .openApp(let id): wire = Wire(type: "openApp", bundleID: id)
        }
        try wire.encode(to: encoder)
    }
}
