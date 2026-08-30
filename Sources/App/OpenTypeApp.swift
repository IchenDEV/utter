import SwiftUI
import AppKit
import Combine

@main
struct OpenTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var hotkeyManager: HotkeyManager?
    private var pipeline: VoicePipeline?
    private var settingsWindow: NSWindow?
    private var settingsWindowDelegate: SettingsWindowDelegate?
    private var onboardingWindow: NSWindow?
    private let popoverOutsideClickMonitor = PopoverOutsideClickMonitor()
    let textProcessor: TextProcessor
    var cancellables = Set<AnyCancellable>()
    var iconTimer: Timer?
    private var previousApp: NSRunningApplication?
    let integrationClientRegistry: IntegrationClientRegistry
    var integrationService: OpenTypeService
    var integrationSessionCoordinator: InputSessionCoordinator!
    var integrationHTTPServer: IntegrationHTTPServer?
    var integrationXPCServer: IntegrationXPCServer?
    var integrationHTTPPort: Int?
    var integrationHTTPToken: String?

    override init() {
        let registry = IntegrationClientRegistry()
        integrationClientRegistry = registry
        integrationService = OpenTypeService(registry: registry)
        textProcessor = TextProcessor()
        super.init()
        integrationSessionCoordinator = makeIntegrationSessionCoordinator(service: integrationService)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIcon.install()
        setupMenuBar()
        setupPipeline()
        setupHotkey()
        observePhaseForIcon()
        observeMenuBarIconSetting()
        observeAppIconSetting()
        observeSystemAppearanceForIcon()
        observeUILanguageForSettingsWindow()
        observeIntegrationSettings()
        configureIntegrationHTTPServer()
        configureIntegrationXPCServer()

        if !AppSettings.shared.hasCompletedOnboarding {
            showOnboarding()
        }

    }

    func applicationWillTerminate(_ notification: Notification) {
        stopIntegrationHTTPServer(resetService: true)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = Self.micIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = MenuBarView(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onApplyPendingReplacement: { [weak self] in
                Task { @MainActor in
                    await self?.applyPendingReplacement()
                }
            },
            onQuit: { NSApp.terminate(nil) }
        )
        .environmentObject(appState)
        .environmentObject(AppSettings.shared)

        popover.contentSize = NSSize(width: 280, height: 220)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupPipeline() {
        pipeline = VoicePipeline(appState: appState, textProcessor: textProcessor)
        Task { await pipeline?.warmUp() }
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager(
            settings: AppSettings.shared,
            onStart: { [weak self] action in
                Task { @MainActor in self?.startRecording(action: action) }
            },
            onStop: { [weak self] _ in
                Task { @MainActor in self?.stopRecording() }
            }
        )
        hotkeyManager?.start()
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            savePreviousApp()
            pipeline?.refreshPendingReplacement()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popoverOutsideClickMonitor.start { [weak self] in
                self?.closePopover()
            }
        }
    }

    private func savePreviousApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
    }

    private func startRecording(action: HotkeyAction) {
        if integrationSessionCoordinator.isBusy {
            pipeline?.showBusyHint()
            return
        }
        savePreviousApp()
        if popover.isShown { closePopover() }
        let mode: VoiceInputMode = action == .translation
            ? .translation(AppSettings.shared.translationTargetLanguage)
            : .dictation
        Task { await pipeline?.start(mode: mode, targetApp: previousApp) }
    }

    private func stopRecording() {
        Task { await pipeline?.stop(targetApp: previousApp) }
    }

    private func applyPendingReplacement() async {
        await pipeline?.applyPendingReplacement()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView {
            AppSettings.shared.hasCompletedOnboarding = true
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ProductBrand.displayName
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false

        onboardingWindow = window

        NSApp.setActivationPolicy(.regular)
        AppIcon.install()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    private func openSettings() {
        if popover.isShown { closePopover() }

        if let existing = settingsWindow, existing.isVisible {
            NSApp.setActivationPolicy(.regular)
            AppIcon.install()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            onUnloadWhisper: { [weak self] in self?.pipeline?.unloadWhisper() },
            onUnloadLLM: { [weak self] in self?.pipeline?.unloadLLM() },
            onLoadLLM: { [weak self] in self?.pipeline?.loadLLM() },
            onBenchmarkLLM: { [weak self] modelID in
                guard let self else { throw CancellationError() }
                return try await self.textProcessor.benchmarkLLM(modelID: modelID)
            },
            onUnloadLocalASR: { [weak self] in self?.pipeline?.unloadLocalASR() }
        )
        .environmentObject(appState)
        .environmentObject(AppSettings.shared)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsWindowLayout.width,
                height: SettingsWindowLayout.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsWindowTitle.current
        window.minSize = NSSize(
            width: SettingsWindowLayout.minimumWidth,
            height: SettingsWindowLayout.minimumHeight
        )
        window.setFrameAutosaveName("UtterSettingsWindow")
        window.center()
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false

        let delegate = SettingsWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = delegate
        settingsWindowDelegate = delegate
        settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        AppIcon.install()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observeUILanguageForSettingsWindow() {
        AppSettings.shared.$uiLanguage
            .sink { [weak self] language in
                self?.settingsWindow?.title = SettingsWindowTitle.text(for: language)
            }
            .store(in: &cancellables)
    }

    private func closePopover() {
        popoverOutsideClickMonitor.stop()
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        popoverOutsideClickMonitor.stop()
    }
}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
