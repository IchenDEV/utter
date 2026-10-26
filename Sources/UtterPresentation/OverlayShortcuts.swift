import Foundation

@MainActor
protocol OverlayShortcutRegistration: AnyObject {
    var onPress: ((UInt32) -> Void)? { get set }
    func register(_ key: OverlayShortcuts.Key, id: UInt32) -> Bool
    func unregister(_ id: UInt32)
    func close()
}

/// Each queued key event belongs to the session/receipt that registered it.
@MainActor
final class OverlayShortcuts {
    enum Key { case cancel, restore }
    enum Action: Hashable { case cancel(UUID), restore(UUID) }
    private let registration: any OverlayShortcutRegistration
    private var bindings: [Action: UInt32] = [:]
    private var nextID: UInt32 = 0
    private var attempted: Set<Action> = []
    private var closed = false
    var onAction: ((Action) -> Void)?

    init(registration: any OverlayShortcutRegistration) {
        self.registration = registration
        registration.onPress = { [weak self] in self?.press($0) }
    }

    func update(cancel: UUID?, restore: UUID?) {
        guard !closed else { return }
        let requested = Set([cancel.map(Action.cancel), restore.map(Action.restore)].compactMap { $0 })
        attempted.formIntersection(requested)
        for (action, id) in bindings where !requested.contains(action) {
            registration.unregister(id); bindings[action] = nil
        }
        for action in requested where bindings[action] == nil && !attempted.contains(action) {
            guard nextID < UInt32.max else { continue }
            nextID += 1
            attempted.insert(action)
            let key: Key
            switch action { case .cancel: key = .cancel; case .restore: key = .restore }
            if registration.register(key, id: nextID) { bindings[action] = nextID }
        }
    }

    func isRegistered(_ action: Action) -> Bool { bindings[action] != nil }

    private func press(_ id: UInt32) {
        guard !closed, let action = bindings.first(where: { $0.value == id })?.key else { return }
        bindings[action] = nil
        registration.unregister(id)
        onAction?(action)
    }

    func close() {
        guard !closed else { return }
        closed = true
        bindings.removeAll(); attempted.removeAll(); onAction = nil
        registration.onPress = nil
        registration.close()
    }
}
