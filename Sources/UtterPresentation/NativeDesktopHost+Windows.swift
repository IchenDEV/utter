import AppKit
import SwiftUI
import UtterContracts
import UtterPresentationContracts

@MainActor
extension NativeDesktopHost {
    func bindSettingsCommand() {
        guard !closed, isCurrent(), let menu = NSApp.mainMenu else { return }
        func find(in menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.keyEquivalent == ",", item.keyEquivalentModifierMask.contains(.command) { return item }
                if let submenu = item.submenu, let found = find(in: submenu) { return found }
            }
            return nil
        }
        guard let item = find(in: menu), settingsCommand?.item !== item else { return }
        restoreSettingsCommand()
        settingsCommand = (item, item.target as AnyObject?, item.action)
        item.target = self
        item.action = #selector(showSettingsWindow(_:))
    }

    func restoreSettingsCommand() {
        if let command = settingsCommand, command.item.target === self {
            command.item.target = command.target
            command.item.action = command.action
        }
        settingsCommand = nil
    }

    @objc private func showSettingsWindow(_ sender: Any?) { openSettings() }

    func openSettings() {
        guard !closed, isCurrent() else { return }
        closePopover()
        if let settingsWindow { activate(settingsWindow); return }
        let sections = catalog.contributions(for: .settings)
        if !sections.contains(where: { $0.id == state.selectedSettingsID }), let first = sections.first {
            state.selectedSettingsID = first.id
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsWindowLayout.contentSize),
            styleMask: SettingsWindowLayout.styleMask, backing: .buffered, defer: false)
        window.setFrameAutosaveName("UtterSettingsWindow")
        window.contentMinSize = SettingsWindowLayout.contentSize
        window.contentMaxSize = SettingsWindowLayout.contentSize
        window.isReleasedWhenClosed = false
        installSettingsContent(in: window)
        windowDelegate = DesktopWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            if self?.onboardingWindow == nil { NSApp.setActivationPolicy(.accessory) }
        }
        window.delegate = windowDelegate
        settingsWindow = window
        window.center()
        activate(window)
    }

    func installSettingsContent(in window: NSWindow) {
        window.title = SettingsWindowTitle.text(for: settings.uiLanguage)
        // Native tab controls need fresh intrinsic sizes after a language change.
        window.contentView = NSHostingView(rootView: SettingsView(
            sections: catalog.contributions(for: .settings), context: context)
            .environmentObject(settings).environmentObject(state))
    }

    func showOnboarding() {
        guard !catalog.contributions(for: .onboarding).isEmpty else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = ProductBrand.displayName
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contributed(.onboarding))
        onboardingWindow = window
        window.center()
        activate(window)
    }

    func completeOnboarding() {
        guard !closed, isCurrent() else { return }
        settings.hasCompletedOnboarding = true
        onboardingWindow?.close(); onboardingWindow = nil
        if settingsWindow == nil { NSApp.setActivationPolicy(.accessory) }
    }

    private func activate(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        icons?.install(appearance: settings.appIconAppearance)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class DesktopWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
