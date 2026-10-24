import Foundation
import Combine
import UtterContracts
import UtterMediaContracts

@MainActor
final class RemoteMicController: RemoteMicControlService {
    private let bridge: XiaomiRemoteMicBridge
    private let isReady: () -> Bool
    private var prepared = false
    private var closed = false
    private var enabled = false
    private var pressed: ((UInt64) -> Void)?
    private var released: (() -> Void)?
    private var stopped: (() -> Void)?
    private var observers: [UUID: (RemoteMicBridgeState) -> Void] = [:]
    private var subscription: AnyCancellable?

    init(bridge: XiaomiRemoteMicBridge, isReady: @escaping () -> Bool) {
        self.bridge = bridge
        self.isReady = isReady
        bridge.onVoiceKeyPressed = { [weak self] token in
            guard let self, !self.closed, self.isReady() else { return }
            self.pressed?(token)
        }
        bridge.onVoiceKeyReleased = { [weak self] in
            guard let self, !self.closed, self.isReady() else { return }
            self.released?()
        }
        bridge.onStreamStopped = { [weak self] in
            guard let self, !self.closed, self.isReady() else { return }
            self.stopped?()
        }
        subscription = bridge.$state.sink { [weak self] state in
            guard let self, !self.closed else { return }
            for observer in Array(self.observers.values) { observer(state) }
        }
    }

    var state: RemoteMicBridgeState { bridge.state }

    func setEnabled(_ enabled: Bool) {
        guard !closed else { return }
        self.enabled = enabled
        guard prepared else { return }
        if enabled { bridge.activate() } else { bridge.deactivate() }
    }

    func prepareIngress() {
        guard !closed else { return }
        prepared = true
        setEnabled(enabled)
    }

    func setVoiceCallbacks(pressed: ((UInt64) -> Void)?, released: (() -> Void)?, stopped: (() -> Void)?) {
        guard !closed else { return }
        self.pressed = pressed
        self.released = released
        self.stopped = stopped
    }

    func observe(_ callback: @escaping (RemoteMicBridgeState) -> Void) -> UUID {
        let id = UUID()
        guard !closed else { return id }
        observers[id] = callback
        callback(state)
        return id
    }

    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    func revoke() {
        guard !closed else { return }
        closed = true
        subscription = nil
        observers.removeAll()
        pressed = nil
        released = nil
        stopped = nil
        bridge.revoke()
    }
}
