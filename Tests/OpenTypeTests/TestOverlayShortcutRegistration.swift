import Foundation
@testable import UtterPresentation

@MainActor
final class TestOverlayShortcutRegistration: OverlayShortcutRegistration {
    var onPress: ((UInt32) -> Void)?
    var keys: [UInt32: OverlayShortcuts.Key] = [:]
    private(set) var attempts = 0
    var rejectsRegistration = false
    private(set) var closed = false
    func register(_ key: OverlayShortcuts.Key, id: UInt32) -> Bool {
        attempts += 1
        guard !closed, !rejectsRegistration else { return false }
        keys[id] = key
        return true
    }
    func unregister(_ id: UInt32) { keys[id] = nil }
    func close() { closed = true; keys.removeAll(); onPress = nil }
    func press(_ id: UInt32) { onPress?(id) }
}
