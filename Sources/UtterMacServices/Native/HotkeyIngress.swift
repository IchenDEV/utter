import Foundation
import UtterContracts

@MainActor
final class HotkeyIngress: HotkeyControlService {
    private let isReady: () -> Bool
    private var prepared = false
    private var closed = false
    private var enabled = true
    private var start: ((HotkeyAction) -> Void)?
    private var stop: ((HotkeyAction) -> Void)?
    private var promote: ((HotkeyPromotion) -> Bool)?
    private var cancel: (() -> Void)?
    private var manager: HotkeyManager?
    var captureID: UUID? { manager?.gestures.captureID }
    var eventTimestamp: Duration? { manager?.eventTimestamp }

    init(settings: any SettingsService, log: Log, isReady: @escaping () -> Bool) {
        self.isReady = isReady
        manager = HotkeyManager(
            settings: { settings.values },
            onStart: { [weak self] action in
                guard let self, !self.closed, self.enabled, self.isReady() else { return }
                self.start?(action)
            },
            onStop: { [weak self] action in
                guard let self, !self.closed, self.isReady() else { return }
                self.stop?(action)
            },
            onPromote: { [weak self] promotion in
                guard let self, !self.closed, self.enabled, self.isReady() else { return false }
                return self.promote?(promotion) ?? false
            }, onCancel: { [weak self] in self?.cancel?() },
            log: log, markAccessibilityPrompted: { settings.update { $0.hotkeyAccessibilityPrompted = true } }
        )
    }

    func setCallbacks(start: ((HotkeyAction) -> Void)?, stop: ((HotkeyAction) -> Void)?,
                      promote: ((HotkeyPromotion) -> Bool)?, cancel: (() -> Void)?) {
        guard !closed else { return }
        self.start = start
        self.stop = stop
        self.promote = promote
        self.cancel = cancel
    }

    func setEnabled(_ enabled: Bool) {
        guard !closed else { return }
        self.enabled = enabled
        guard prepared else { return }
        if enabled { manager?.start() } else { manager?.stop() }
    }

    func prepareIngress() { prepared = true; setEnabled(enabled) }

    func revoke() {
        guard !closed else { return }
        closed = true
        start = nil
        stop = nil
        promote = nil
        cancel = nil
        manager?.stop()
    }

    func close() async {
        revoke()
        await manager?.close()
        manager = nil
    }
}
