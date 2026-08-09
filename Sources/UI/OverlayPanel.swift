import AppKit
import SwiftUI

final class OverlayPanel {
    private var window: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    @MainActor
    func show(
        appState: AppState,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        let initialLayout = OverlayLayout(appState: appState)

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: initialLayout.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = !initialLayout.isInteractive
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = OverlayContentView(
                onLayoutChange: { [weak self] layout in
                    Task { @MainActor in
                        self?.apply(layout: layout, animated: true)
                    }
                },
                onCancel: onCancel,
                onConfirm: onConfirm
            )
            .environmentObject(appState)

            let hostingView = NSHostingView(rootView: AnyView(view))
            hostingView.frame = NSRect(origin: .zero, size: initialLayout.panelSize)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.layer?.isOpaque = false
            hostingView.layer?.masksToBounds = true
            panel.contentView = hostingView

            self.window = panel
            self.hostingView = hostingView
        }

        apply(layout: initialLayout, animated: false)
        window?.orderFrontRegardless()
    }

    @MainActor
    func hide() {
        window?.close()
        window = nil
        hostingView = nil
    }

    @MainActor
    private func apply(layout: OverlayLayout, animated: Bool) {
        guard let window, let hostingView else { return }
        let frame = frame(for: layout.panelSize, window: window)
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        hostingView.frame = NSRect(origin: .zero, size: layout.panelSize)
        hostingView.layer?.cornerRadius = layout.outerCornerRadius
        hostingView.layer?.cornerCurve = .continuous
        window.ignoresMouseEvents = !layout.isInteractive
        window.setFrame(frame, display: true, animate: shouldAnimate)
    }

    @MainActor
    private func frame(for size: CGSize, window: NSWindow) -> NSRect {
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        return OverlayPanelPlacement.frame(for: size, in: visibleFrame)
    }
}

enum OverlayPanelPlacement {
    static let bottomMargin: CGFloat = 24

    static func frame(for size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + bottomMargin,
            width: size.width,
            height: size.height
        )
    }
}
