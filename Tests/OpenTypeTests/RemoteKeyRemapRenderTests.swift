import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
private final class RenderRemoteControl: RemoteMicControlService {
    var state: RemoteMicBridgeState = .idle
    var diagnostics: RemoteMicDiagnostics
    init(_ diagnostics: RemoteMicDiagnostics) { self.diagnostics = diagnostics }
    func reconnect() {}
    func observeDiagnostics(_ callback: @escaping (RemoteMicDiagnostics) -> Void) -> UUID {
        callback(diagnostics)
        return UUID()
    }
    func setEnabled(_ enabled: Bool) {}
    func setVoiceCallbacks(pressed: ((UInt64) -> Void)?, released: (() -> Void)?, stopped: (() -> Void)?) {}
    func observe(_ callback: @escaping (RemoteMicBridgeState) -> Void) -> UUID {
        callback(state)
        return UUID()
    }
    func removeObserver(_ id: UUID) {}
}

/// Renders the real Remote settings page into an AppKit window for visual QA. It writes PNGs
/// only when `UTTER_RENDER_DIR` is set, so normal test runs are unaffected.
@MainActor
final class RemoteKeyRemapRenderTests: XCTestCase {
    private func render(
        state: RemoteKeyRemapState, enabled: Bool, language: UILanguage, dark: Bool, to url: URL
    ) throws {
        Loc.use(language)
        let values = RemotePluginSettings()
        values.values.remoteKeyRemapEnabled = enabled
        let settings = AppSettings(service: values)
        let control = RenderRemoteControl(RemoteMicDiagnostics(keyRemap: state))
        let platform = PlatformProjection(remote: control, login: nil, devices: nil, screen: nil,
                                          diagnostics: RemotePluginDiagnostics())
        let view = Form { RemoteMicSettingsView(platform: platform) }
            .formStyle(.grouped)
            .environmentObject(settings)
            .environmentObject(platform)
            .frame(width: 620, height: 360)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    func testRenderRemotePageVariants() throws {
        guard let directory = ProcessInfo.processInfo.environment["UTTER_RENDER_DIR"] else {
            throw XCTSkip("Set UTTER_RENDER_DIR to write visual QA screenshots.")
        }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { Loc.use(.chinese) }
        let cases: [(RemoteKeyRemapState, Bool, String)] = [
            (.active, true, "active"), (.waitingForService, true, "waiting"), (.noRemote, true, "no-remote"),
            (.conflict, true, "conflict"), (.failed, true, "failed"), (.off, false, "setting-off"),
        ]
        for language in [UILanguage.english, .chinese] {
            for dark in [false, true] {
                for (state, enabled, name) in cases {
                    let file = "remote-key-\(name)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                    try render(state: state, enabled: enabled, language: language, dark: dark,
                               to: root.appendingPathComponent(file))
                }
            }
        }
    }
}
