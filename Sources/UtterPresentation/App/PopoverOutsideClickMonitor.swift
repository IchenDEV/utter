import AppKit

@MainActor
final class PopoverOutsideClickMonitor {
    private var monitor: Any?

    func start(onOutsideClick: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            Task { @MainActor in
                onOutsideClick()
            }
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
