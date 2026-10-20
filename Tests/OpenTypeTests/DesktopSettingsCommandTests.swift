import AppKit
import XCTest
import UtterContracts
import UtterData
@testable import UtterPresentation

@MainActor
final class DesktopSettingsCommandTests: XCTestCase {
    func testStandardSettingsCommandOpensDesktopSettingsAndRestoresOnClose() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        defer { app.mainMenu = previousMenu }
        let receiver = SettingsCommandReceiver()
        let menu = NSMenu()
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(SettingsCommandReceiver.open(_:)),
                                      keyEquivalent: ",")
        settingsItem.target = receiver
        appMenu.addItem(settingsItem)
        app.mainMenu = menu

        let suite = "DesktopSettingsCommand-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "hasCompletedOnboarding")
        let settings = SettingsStore(defaults: defaults)
        let host = NativeDesktopHost(catalog: PresentationRegistry(), settings: settings,
            credentials: SettingsCredentialsService(settings: settings), execution: nil, outputs: nil,
            overlay: nil, icons: nil, diagnostics: SettingsCommandDiagnostics(), isCurrent: { true })
        defer { host.close() }
        host.start()
        host.settingsWindow?.close()
        XCTAssertNil(host.settingsWindow)

        appMenu.performActionForItem(at: 0)
        XCTAssertNotNil(host.settingsWindow, "The standard command must open the owned settings window")
        XCTAssertEqual(host.settingsWindow?.contentView?.frame.size, NSSize(width: 760, height: 680))
        XCTAssertEqual(receiver.calls, 0, "The empty SwiftUI settings action must not run")

        host.close()
        appMenu.performActionForItem(at: 0)
        XCTAssertEqual(receiver.calls, 1, "Revoking the desktop host must restore the original action")
    }
}

@MainActor
private final class SettingsCommandReceiver: NSObject {
    var calls = 0
    @objc func open(_ sender: Any?) { calls += 1 }
}

private struct SettingsCommandDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
