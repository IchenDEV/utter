import AppKit
import Combine
import SwiftUI
import UtterContracts
import UtterPresentationContracts

@MainActor
final class NativeDesktopHost: NSObject, DesktopPresentationService, NSPopoverDelegate {
    let catalog: any PresentationCatalog
    let settings: AppSettings
    let state = AppState()
    let execution: (any SessionExecutionService)?
    let outputs: (any SessionOutputStateService)?
    let overlay: (any OverlayPresentationService)?
    let icons: (any IconPresentationService)?
    let diagnostics: any DiagnosticsService
    let isCurrent: () -> Bool
    var statusItem: NSStatusItem?
    let popover = NSPopover()
    let outsideClicks = PopoverOutsideClickMonitor()
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var windowDelegate: DesktopWindowDelegate?
    var subscriptions: Set<AnyCancellable> = []
    var hideTask: Task<Void, Never>?
    var executionObserver: UUID?
    var outputObserver: UUID?
    var closed = false

    init(catalog: any PresentationCatalog, settings: any SettingsService, credentials: any CredentialsService,
         execution: (any SessionExecutionService)?, outputs: (any SessionOutputStateService)?,
         overlay: (any OverlayPresentationService)?, icons: (any IconPresentationService)?,
         diagnostics: any DiagnosticsService, isCurrent: @escaping () -> Bool) {
        self.catalog = catalog; self.settings = AppSettings(service: settings, credentials: credentials)
        self.execution = execution; self.outputs = outputs; self.overlay = overlay; self.icons = icons
        self.diagnostics = diagnostics; self.isCurrent = isCurrent
        super.init()
    }

    var context: PresentationContext {
        PresentationContext(settings: settings, state: state,
            openSettings: { [weak self] in self?.openSettings() },
            applyReplacement: { [weak self] in self?.applyReplacement() },
            copy: { [weak self] in self?.copy($0) },
            completeOnboarding: { [weak self] in self?.completeOnboarding() },
            dismiss: { [weak self] in self?.overlay?.hide() },
            cancel: { [weak self] in self?.cancel() },
            stop: { [weak self] in self?.stop() },
            recover: { [weak self] in self?.recover() })
    }

    func start() {
        guard !closed, isCurrent() else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: contributed(.menu))
        executionObserver = execution?.observe { [weak self] in self?.project($0) }
        outputObserver = outputs?.observe { [weak self] in self?.state.project($0) }
        settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.closed, self.isCurrent() else { return }
                self.refreshIcons()
                self.settingsWindow?.title = SettingsWindowTitle.text(for: self.settings.uiLanguage)
            }
        }.store(in: &subscriptions)
        NSApp.publisher(for: \.effectiveAppearance).sink { [weak self] _ in self?.refreshIcons() }.store(in: &subscriptions)
        refreshIcons()
        if !settings.hasCompletedOnboarding { showOnboarding() }
        if execution == nil { openSettings() }
    }

    func contributed(_ role: PresentationRole) -> some View {
        let presentation = context
        return VStack(spacing: 0) {
            ForEach(catalog.contributions(for: role), id: \.id) { $0.view(presentation) }
        }.environmentObject(settings).environmentObject(state)
    }

    func project(_ snapshot: SessionExecutionSnapshot) {
        guard !closed, isCurrent() else { return }
        state.project(snapshot)
        refreshIcons()
        hideTask?.cancel()
        guard snapshot.phase != nil, snapshot.phase != .cancelled else { overlay?.hide(); return }
        if snapshot.isBusy { closePopover() }
        let target = NSWorkspace.shared.frontmostApplication
        overlay?.show(context: context, targetApp: target)
        if !snapshot.isBusy && !state.presentation.keepsVisible {
            hideTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                guard let self, !self.closed, self.isCurrent(), self.state.snapshot.id == snapshot.id else { return }
                self.overlay?.hide()
            }
        }
    }

    func refreshIcons() {
        guard !closed, isCurrent() else { return }
        icons?.install(appearance: settings.appIconAppearance)
        statusItem?.button?.image = icons?.menuIcon(settings.menuBarIcon, phase: state.phase)
    }

    @objc func togglePopover() {
        guard !closed, isCurrent(), let button = statusItem?.button else { return }
        if popover.isShown { closePopover(); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        outsideClicks.start { [weak self] in self?.closePopover() }
    }

    func closePopover() { outsideClicks.stop(); popover.performClose(nil) }
    func popoverDidClose(_ notification: Notification) { outsideClicks.stop() }

    func close() {
        guard !closed else { return }
        closed = true
        hideTask?.cancel(); hideTask = nil
        if let executionObserver { execution?.removeObserver(executionObserver) }
        if let outputObserver { outputs?.removeObserver(outputObserver) }
        executionObserver = nil; outputObserver = nil
        subscriptions.removeAll()
        overlay?.hide(); closePopover()
        popover.contentViewController = nil
        settingsWindow?.close(); settingsWindow = nil
        onboardingWindow?.close(); onboardingWindow = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
