import AppKit
import ApplicationServices
import SwiftUI

final class OverlayPanel {
    private var window: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var targetDisplayID: CGDirectDisplayID?

    @MainActor
    func show(
        appState: AppState,
        targetApp: NSRunningApplication?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        let initialLayout = OverlayLayout(appState: appState)
        targetDisplayID = OverlayTargetScreenResolver.displayID(for: targetApp)

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
        targetDisplayID = nil
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
        let screen = OverlayTargetScreenResolver.screen(with: targetDisplayID)
            ?? NSScreen.main
            ?? window.screen
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        return OverlayPanelPlacement.frame(for: size, in: visibleFrame)
    }
}

@MainActor
enum OverlayTargetScreenResolver {
    static func displayID(for app: NSRunningApplication?) -> CGDirectDisplayID? {
        guard let windowFrame = focusedWindowFrame(for: app) else {
            return NSScreen.main.flatMap(displayID(for:))
        }

        let screens = NSScreen.screens
        // AX window geometry and CG display bounds share the same global coordinate space.
        let displayFrames = screens.map { screen in
            displayID(for: screen).map(CGDisplayBounds) ?? .null
        }
        guard let index = OverlayPanelPlacement.targetDisplayIndex(
            for: windowFrame,
            in: displayFrames
        ) else {
            return NSScreen.main.flatMap(displayID(for:))
        }
        return displayID(for: screens[index])
    }

    static func screen(with displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { self.displayID(for: $0) == displayID }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func focusedWindowFrame(for app: NSRunningApplication?) -> CGRect? {
        guard let app, AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)

        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let frame = windowFrame(from: application, attribute: attribute as CFString) else {
                continue
            }
            return frame
        }
        return nil
    }

    private static func windowFrame(from application: AXUIElement, attribute: CFString) -> CGRect? {
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute, &windowValue) == .success,
              let rawWindow = windowValue,
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            return nil
        }

        let window = rawWindow as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
              AXUIElementCopyAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                &sizeValue
              ) == .success,
              let rawPosition = positionValue,
              let rawSize = sizeValue,
              CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              CFGetTypeID(rawSize) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
              position.x.isFinite,
              position.y.isFinite,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

enum OverlayPanelPlacement {
    static let bottomMargin: CGFloat = 24

    static func targetDisplayIndex(for windowFrame: CGRect, in displayFrames: [CGRect]) -> Int? {
        displayFrames.indices
            .map { index in
                (index: index, overlap: overlapArea(windowFrame, displayFrames[index]))
            }
            .filter { $0.overlap > 0 }
            .max { lhs, rhs in lhs.overlap < rhs.overlap }?
            .index
    }

    static func frame(for size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + bottomMargin,
            width: size.width,
            height: size.height
        )
    }

    private static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
