import AppKit
import SwiftUI
import UtterBuiltins
import UtterContracts

@main
struct OpenTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var application: BuiltinApplication?
    private var startup: Task<Void, Never>?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        startup = Task { [weak self] in
            do {
                let application = try await BuiltinApplication.start()
                guard let self, !self.terminating, !Task.isCancelled else {
                    try await application.stop()
                    return
                }
                self.application = application
                if application.compositionFailure != nil { self.showFailure(L("plugins.recovery")) }
            } catch {
                guard let self, !self.terminating, !Task.isCancelled else { return }
                self.showFailure(L("plugins.recovery"))
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        startup?.cancel()
        Task { [self] in
            await startup?.value
            do {
                try await application?.stop()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminating = false
                showFailure(L("error.operation_failed"))
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    private func showFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = ProductBrand.displayName
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("common.ok"))
        alert.runModal()
    }
}
