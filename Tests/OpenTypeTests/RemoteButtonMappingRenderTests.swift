import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
private final class ButtonRenderRemote: RemoteMicControlService {
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

/// Renders the real Remote settings page with the button mapping into an AppKit window for visual QA.
/// It writes PNGs only when `UTTER_RENDER_DIR` is set; otherwise it renders one variant to prove the
/// page lays out.
@MainActor
final class RemoteButtonMappingRenderTests: XCTestCase {
    private struct Variant {
        var name: String
        var state: RemoteButtonMappingState
        var mappingOn = true
        var remapOn = true
        var profile = RemoteButtonMappingRenderTests.sampleProfile
        var language = UILanguage.english
        var dark = false
    }

    private nonisolated static var sampleProfile: RemoteButtonProfile {
        var profile = RemoteButtonProfile()
        profile.set(.showDesktop, for: .single, of: .home)
        profile.set(.appSwitcher, for: .double, of: .home)
        profile.set(.key(KeyChord(keyCode: 33, modifiers: .command)), for: .single, of: .back)
        profile.set(.openApp(bundleID: "com.apple.Safari"), for: .long, of: .ok)
        profile.set(.system(.playPause), for: .single, of: .tv)
        profile.set(.system(.previous), for: .single, of: .left)
        profile.set(.system(.next), for: .single, of: .right)
        profile.set(.system(.mute), for: .long, of: .volumeDown)
        return profile
    }

    private func render(_ variant: Variant, to url: URL?) throws {
        Loc.use(variant.language)
        let store = RemotePluginSettings()
        store.values.remoteKeyRemapEnabled = variant.remapOn
        store.values.remoteButtonMappingEnabled = variant.mappingOn
        store.values.remoteButtonProfile = variant.profile
        let settings = AppSettings(service: store)
        let control = ButtonRenderRemote(RemoteMicDiagnostics(keyRemap: .active, buttonMapping: variant.state))
        let platform = PlatformProjection(remote: control, login: nil, devices: nil, screen: nil,
                                          diagnostics: RemotePluginDiagnostics())
        let size = NSSize(width: 620, height: 1020)
        let view = RemoteMicSettingsView()
            .environmentObject(settings)
            .environmentObject(platform)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: variant.dark ? .darkAqua : .aqua)
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000, variant.name)
        try url.map { try png.write(to: $0) }
    }

    func testRenderButtonMappingPageVariants() throws {
        let variants = [
            Variant(name: "active-en-light", state: .active),
            Variant(name: "active-en-dark", state: .active, dark: true),
            Variant(name: "active-zh-light", state: .active, language: .chinese),
            Variant(name: "active-zh-dark", state: .active, language: .chinese, dark: true),
            Variant(name: "off-en-light", state: .off, mappingOn: false),
            Variant(name: "ask-en-light", state: .needsPermission(canAsk: true)),
            Variant(name: "denied-en-light", state: .needsPermission(canAsk: false)),
            Variant(name: "restart-en-light", state: .needsRestart),
            Variant(name: "conflict-en-light", state: .conflict),
            Variant(name: "conflict-zh-dark", state: .conflict, language: .chinese, dark: true),
            Variant(name: "waiting-en-light", state: .waitingForRemote, profile: RemoteButtonProfile()),
            Variant(name: "remap-off-en-light", state: .off, mappingOn: true, remapOn: false),
        ]
        guard let directory = ProcessInfo.processInfo.environment["UTTER_RENDER_DIR"] else {
            try render(variants[0], to: nil)
            return
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for variant in variants {
            try render(variant, to: folder.appendingPathComponent("remote-buttons-\(variant.name).png"))
        }
    }
}
