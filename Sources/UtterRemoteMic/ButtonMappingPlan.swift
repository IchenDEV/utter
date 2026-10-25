import Foundation

/// What the profile asks of the remote right now: which buttons Utter owns, and for each, the
/// `UserKeyMapping` source that silences its native key and how its gestures resolve.
package struct ButtonMappingPlan: Equatable, Sendable {
    package struct Owned: Equatable, Sendable {
        package var button: RemoteButton
        package var hidSource: UInt64
        package var gestures: GestureBindings
    }

    package var owned: [Owned]

    package static func make(from profile: RemoteButtonProfile) -> ButtonMappingPlan {
        ButtonMappingPlan(owned: profile.ownedButtons.map { button in
            let bindings = profile.bindings(for: button)
            return Owned(
                button: button,
                hidSource: button.hidSource,
                gestures: GestureBindings(hasDouble: bindings.double != .native, hasLong: bindings.long != .native)
            )
        })
    }

    package var isEmpty: Bool { owned.isEmpty }
    package var sources: [UInt64] { owned.map(\.hidSource) }
}
