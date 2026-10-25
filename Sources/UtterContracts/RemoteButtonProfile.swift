import Foundation

package struct ButtonBindings: Equatable, Sendable {
    package var single: ButtonAction = .native
    package var double: ButtonAction = .native
    package var long: ButtonAction = .native

    package init(single: ButtonAction = .native, double: ButtonAction = .native, long: ButtonAction = .native) {
        self.single = single
        self.double = double
        self.long = long
    }

    package func action(for trigger: ButtonTrigger) -> ButtonAction {
        switch trigger {
        case .single: single
        case .double: double
        case .long: long
        }
    }

    package var isNative: Bool { single == .native && double == .native && long == .native }

    fileprivate mutating func set(_ action: ButtonAction, for trigger: ButtonTrigger) {
        switch trigger {
        case .single: single = action
        case .double: double = action
        case .long: long = action
        }
    }
}

/// The user's choices: per button, one action per trigger. Only buttons with at least one
/// non-`native` action are stored, so an untouched profile is empty and owns nothing.
package struct RemoteButtonProfile: Equatable, Sendable {
    package static let currentVersion = 1

    package private(set) var bindings: [RemoteButton: ButtonBindings] = [:]

    package init() {}

    package func bindings(for button: RemoteButton) -> ButtonBindings { bindings[button] ?? ButtonBindings() }

    package var isEmpty: Bool { bindings.isEmpty }

    package func isOwned(_ button: RemoteButton) -> Bool { bindings[button] != nil }

    /// In the fixed order of `RemoteButton.allCases`, so the result never depends on dictionary order.
    package var ownedButtons: [RemoteButton] { RemoteButton.allCases.filter(isOwned) }

    package mutating func set(_ action: ButtonAction, for trigger: ButtonTrigger, of button: RemoteButton) {
        var current = bindings(for: button)
        current.set(action, for: trigger)
        bindings[button] = current.isNative ? nil : current
    }

    package mutating func restoreDefaults() { bindings = [:] }
}

extension RemoteButtonProfile: Codable {
    private struct Wire: Codable {
        var version: Int
        var buttons: [String: Triggers]
    }

    private struct Triggers: Codable {
        var single: ButtonAction?
        var double: ButtonAction?
        var long: ButtonAction?
    }

    /// Unknown buttons are ignored and an unknown action is `native`, so a profile written by a
    /// newer version still yields everything this version understands.
    package init(from decoder: Decoder) throws {
        let wire = try Wire(from: decoder)
        var profile = RemoteButtonProfile()
        for (name, triggers) in wire.buttons {
            guard let button = RemoteButton(rawValue: name) else { continue }
            profile.set(triggers.single ?? .native, for: .single, of: button)
            profile.set(triggers.double ?? .native, for: .double, of: button)
            profile.set(triggers.long ?? .native, for: .long, of: button)
        }
        self = profile
    }

    package func encode(to encoder: Encoder) throws {
        var buttons: [String: Triggers] = [:]
        for (button, value) in bindings {
            buttons[button.rawValue] = Triggers(single: value.single, double: value.double, long: value.long)
        }
        try Wire(version: Self.currentVersion, buttons: buttons).encode(to: encoder)
    }

    /// Never throws: nothing stored, or stored data that cannot be read, is an empty profile.
    package static func decode(_ data: Data?) -> RemoteButtonProfile {
        guard let data, let profile = try? JSONDecoder().decode(RemoteButtonProfile.self, from: data) else {
            return RemoteButtonProfile()
        }
        return profile
    }

    package func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
