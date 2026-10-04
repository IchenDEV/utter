import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class PresentationRenderingTests: XCTestCase {
    func testSettingsAndDeliveryStatesRenderInLightAndDarkWindows() async throws {
        _ = NSApplication.shared
        let suite = "PresentationRendering-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(service: SettingsStore(defaults: defaults))
        Loc.use(.chinese)
        defer { Loc.use(.chinese) }
        let platform = PlatformProjection(remote: nil, login: nil, devices: nil, screen: nil, diagnostics: RenderingDiagnostics())
        defer { platform.dispose() }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = name == .aqua ? "light" : "dark"
            try await render(AnyView(GeneralSettingsView().environmentObject(settings).environmentObject(platform)),
                size: NSSize(width: 760, height: 680), appearance: name, file: "settings-\(suffix)")
            for (label, snapshot) in [
                ("recording", SessionExecutionSnapshot(phase: .recording, transcript: "今天确认三件事。", isBusy: true)),
                ("copied", SessionExecutionSnapshot(phase: .completed, text: "今天确认 3 件事。", deliveryStatus: .copied)),
                ("uncertain", SessionExecutionSnapshot(phase: .failed, text: "今天确认 3 件事。", deliveryStatus: .uncertain)),
                ("models", SessionExecutionSnapshot(phase: .failed, error: L("pipeline.model_load_failed"), recoveryAction: .models)),
            ] {
                let state = AppState()
                state.project(snapshot)
                let view = OverlayContentView(onLayoutChange: { _ in }, onCancel: {}, onConfirm: {},
                    onCopy: {}, onRecover: {}, onDismiss: {}).environmentObject(state)
                let layout = OverlayLayout(appState: state)
                try await render(AnyView(view), size: layout.panelSize, appearance: name, file: "hud-\(label)-\(suffix)")
            }
        }
        Loc.use(.english)
        let state = AppState()
        state.project(SessionExecutionSnapshot(phase: .failed, error: L("pipeline.model_load_failed"), recoveryAction: .models))
        let view = OverlayContentView(onLayoutChange: { _ in }, onCancel: {}, onConfirm: {},
            onCopy: {}, onRecover: {}, onDismiss: {}).environmentObject(state)
        try await render(AnyView(view), size: OverlayLayout(appState: state).panelSize, appearance: .aqua, file: "hud-models-english")
    }

    func testOverlayExcludesItsActualWindowAndReleasesThatIdentityOnHide() throws {
        _ = NSApplication.shared
        let screen = RenderingScreen()
        let panel = OverlayPanel(screen: screen)
        let state = AppState()
        state.project(SessionExecutionSnapshot(phase: .recording, isBusy: true))
        panel.show(appState: state, targetApp: nil, onCancel: {}, onConfirm: {}, onCopy: {}, onRecover: {}, onDismiss: {})
        XCTAssertEqual(screen.excluded.count, 1)
        XCTAssertTrue(try XCTUnwrap(screen.excluded.first) > 0)
        panel.hide()
        XCTAssertEqual(screen.included, screen.excluded)
    }

    private func render(_ view: AnyView, size: NSSize, appearance: NSAppearance.Name, file: String) async throws {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        hosting.setFrameSize(size)
        try await Task.sleep(for: .milliseconds(250))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            let encoded = png.base64EncodedString()
            let characters = Array(encoded)
            for start in stride(from: 0, to: characters.count, by: 768) {
                let chunk = String(characters[start..<min(start + 768, characters.count)])
                FileHandle.standardError.write(Data("UTTER_UI_RENDER \(file) \(start / 768) \(chunk)\n".utf8))
            }
        }
        if let destination = ProcessInfo.processInfo.environment["UTTER_UI_SNAPSHOTS"] {
            let directory = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(file + ".png"))
        }
    }
}

private struct RenderingDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
@MainActor
private final class RenderingScreen: ScreenCaptureService {
    var excluded: [UInt32] = []
    var included: [UInt32] = []
    func excludeWindow(_ id: UInt32) { excluded.append(id) }
    func includeWindow(_ id: UInt32) { included.append(id) }
    func capture(mode: ScreenContextMode) async throws -> ScreenContextSnapshot { .empty }
    func checkPermission() async throws -> Bool { false }
    func requestPermission() {}
}
