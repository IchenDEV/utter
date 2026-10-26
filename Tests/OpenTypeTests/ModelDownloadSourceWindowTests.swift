import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class ModelDownloadSourceWindowTests: XCTestCase {
    func testRenderOnboardingSourceLayouts() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["UTTER_SOURCE_LAYOUT_OUTPUT"] else { throw XCTSkip("Opt-in headless layout evidence") }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = try await ModelSourceIntegration.start()
        let catalog = ModelCatalogProjection(service: fixture.catalog)
        let lifecycle = ModelLifecycleProjection(service: SourceWindowLifecycle())
        let platform = PlatformProjection(remote: nil, login: nil, devices: nil, screen: nil, diagnostics: ModelSourceDiagnostics())
        let state = AppState()
        fixture.settings.modelDownloadSource = .hfMirror
        for language in [UILanguage.chinese, .english] {
            fixture.settings.uiLanguage = language
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let view = OnboardingView(onComplete: {}, step: 2, catalog: catalog, storage: fixture.storage)
                    .environmentObject(fixture.settings).environmentObject(platform)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: appearance)
                host.frame = NSRect(x: 0, y: 0, width: 480, height: 420)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("onboarding-\(language.rawValue)-\(appearance.rawValue).png"))
                let models = ModelManagementView(catalog: catalog, storage: fixture.storage, lifecycle: lifecycle, remoteConnection: nil)
                    .environmentObject(fixture.settings).environmentObject(state)
                let modelHost = NSHostingView(rootView: models)
                modelHost.appearance = NSAppearance(named: appearance)
                modelHost.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
                modelHost.layoutSubtreeIfNeeded()
                let modelBitmap = try XCTUnwrap(modelHost.bitmapImageRepForCachingDisplay(in: modelHost.bounds))
                modelHost.cacheDisplay(in: modelHost.bounds, to: modelBitmap)
                let modelData = try XCTUnwrap(modelBitmap.representation(using: .png, properties: [:]))
                try modelData.write(to: directory.appendingPathComponent("models-\(language.rawValue)-\(appearance.rawValue).png"))
            }
        }
        catalog.dispose(); lifecycle.dispose(); platform.dispose()
        try await fixture.close()
    }

    func testInteractiveSourceWindows() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UTTER_SOURCE_UI_QA"] == "1" else { throw XCTSkip("Opt-in native window verification") }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.finishLaunching()
        let fixture = try await ModelSourceIntegration.start(
            suite: environment["UTTER_SOURCE_QA_SUITE"] ?? "UtterSourceQA-\(UUID().uuidString)",
            root: URL(fileURLWithPath: environment["UTTER_SOURCE_QA_ROOT"] ?? NSTemporaryDirectory() + UUID().uuidString))
        let catalog = ModelCatalogProjection(service: fixture.catalog)
        let lifecycle = ModelLifecycleProjection(service: SourceWindowLifecycle())
        let platform = PlatformProjection(remote: nil, login: nil, devices: nil, screen: nil, diagnostics: ModelSourceDiagnostics())
        let state = AppState()
        let models = ModelManagementView(catalog: catalog, storage: fixture.storage, lifecycle: lifecycle, remoteConnection: nil)
            .environmentObject(fixture.settings).environmentObject(state)
        let onboarding = OnboardingView(onComplete: {}, step: 2, catalog: catalog, storage: fixture.storage)
            .environmentObject(fixture.settings).environmentObject(platform)
        let modelWindow = window("Utter source QA - Models", size: NSSize(width: 760, height: 680), view: models)
        let onboardingWindow = window("Utter source QA - Onboarding", size: NSSize(width: 480, height: 420), view: onboarding)
        let controls = SourceWindowControls(settings: fixture.settings, windows: [modelWindow, onboardingWindow])
        let controlWindow = window("Utter source QA - Controls", size: NSSize(width: 420, height: 120), view: controls)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        modelWindow.setFrameOrigin(NSPoint(x: 20, y: 120))
        onboardingWindow.setFrameOrigin(NSPoint(x: 800, y: 250))
        controlWindow.setFrameOrigin(NSPoint(x: 800, y: 120))
        while !controls.finished.value {
            try await Task.sleep(for: .milliseconds(100))
        }
        [modelWindow, onboardingWindow, controlWindow].forEach { $0.close() }
        catalog.dispose(); lifecycle.dispose(); platform.dispose()
        try await fixture.close(remove: environment["UTTER_SOURCE_QA_KEEP"] != "1")
    }

    private func window<Content: View>(_ title: String, size: NSSize, view: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

@MainActor
private final class SourceWindowFinished { var value = false }

@MainActor
private struct SourceWindowControls: View {
    @ObservedObject var settings: AppSettings
    let windows: [NSWindow]
    let finished = SourceWindowFinished()

    var body: some View {
        VStack {
            HStack {
                Button("Models") { windows[0].makeKeyAndOrderFront(nil) }
                Button("Onboarding") { windows[1].makeKeyAndOrderFront(nil) }
            }
            HStack {
                Button("中文") { settings.uiLanguage = .chinese }
                Button("English") { settings.uiLanguage = .english }
                Button("Light") { windows.forEach { $0.appearance = NSAppearance(named: .aqua) } }
                Button("Dark") { windows.forEach { $0.appearance = NSAppearance(named: .darkAqua) } }
                Button("Finish") { finished.value = true }
            }
            Text("Isolated native views. Model loading controls are unavailable in this UI fixture.")
                .font(.caption)
        }.padding(8)
    }
}

@MainActor
private final class SourceWindowLifecycle: ModelLifecycleService {
    var snapshot = ModelLifecycleSnapshot()
    func observe(_ callback: @escaping (ModelLifecycleSnapshot) -> Void) -> UUID { UUID() }
    func removeObserver(_ id: UUID) {}
    func preloadSpeech() async throws { throw GenerationServiceError.unsupportedOperation }
    func preloadText() async throws { throw GenerationServiceError.unsupportedOperation }
    func unloadSpeech(providerID: String?) async throws {}
    func unloadText() async throws {}
    func benchmark(_ modelID: String) async throws -> ModelBenchmarkResult { throw GenerationServiceError.unsupportedOperation }
    func validateBundle(at url: URL) async throws { throw GenerationServiceError.unsupportedOperation }
}
