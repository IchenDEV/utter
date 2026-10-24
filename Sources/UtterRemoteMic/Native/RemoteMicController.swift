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
    private var diagnosticsSubscription: AnyCancellable?
    private var diagnosticsObservers: [UUID: (RemoteMicDiagnostics) -> Void] = [:]
    private var keyRemap = RemoteKeyRemapState.off
    private var keyRemapReapplyCount = 0
    var onBridgeReady: (() -> Void)?

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
        diagnosticsSubscription = bridge.$diagnostics.sink { [weak self] diagnostics in
            guard let self, !self.closed else { return }
            let merged = self.merged(diagnostics)
            for observer in Array(self.diagnosticsObservers.values) { observer(merged) }
        }
        subscription = bridge.$state.sink { [weak self] state in
            guard let self, !self.closed else { return }
            for observer in Array(self.observers.values) { observer(state) }
            if state.isReady { self.onBridgeReady?() }
        }
    }

    var state: RemoteMicBridgeState { bridge.state }
    var diagnostics: RemoteMicDiagnostics { merged(bridge.diagnostics) }

    func setKeyRemap(_ state: RemoteKeyRemapState, reapplyCount: Int) {
        guard !closed, state != keyRemap || reapplyCount != keyRemapReapplyCount else { return }
        keyRemap = state
        keyRemapReapplyCount = reapplyCount
        let current = diagnostics
        for observer in Array(diagnosticsObservers.values) { observer(current) }
    }

    private func merged(_ diagnostics: RemoteMicDiagnostics) -> RemoteMicDiagnostics {
        var result = diagnostics
        result.keyRemap = keyRemap
        result.keyRemapReapplyCount = keyRemapReapplyCount
        return result
    }

    func reconnect() {
        guard !closed, prepared, enabled else { return }
        bridge.reconnectNow()
    }

    func observeDiagnostics(_ callback: @escaping (RemoteMicDiagnostics) -> Void) -> UUID {
        let id = UUID()
        guard !closed else { return id }
        diagnosticsObservers[id] = callback
        callback(diagnostics)
        return id
    }

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

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
        diagnosticsObservers.removeValue(forKey: id)
    }

    func revoke() {
        guard !closed else { return }
        closed = true
        subscription = nil
        diagnosticsSubscription = nil
        diagnosticsObservers.removeAll()
        observers.removeAll()
        pressed = nil
        released = nil
        stopped = nil
        onBridgeReady = nil
        bridge.revoke()
    }
}
