import UtterContracts

@MainActor
final class HotkeyIngress: HotkeyControlService {
    private let isReady: () -> Bool
    private var prepared = false
    private var closed = false
    private var enabled = true
    private var start: ((HotkeyAction) -> Void)?
    private var stop: ((HotkeyAction) -> Void)?
    private var manager: HotkeyManager?

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
            log: log, markAccessibilityPrompted: { settings.update { $0.hotkeyAccessibilityPrompted = true } }
        )
    }

    func setCallbacks(start: ((HotkeyAction) -> Void)?, stop: ((HotkeyAction) -> Void)?) {
        guard !closed else { return }
        self.start = start
        self.stop = stop
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
        manager?.stop()
    }

    func close() async {
        revoke()
        await manager?.close()
        manager = nil
    }
}
