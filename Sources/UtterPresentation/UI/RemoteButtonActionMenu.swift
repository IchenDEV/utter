import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UtterContracts
import UtterPresentationContracts

/// One cell of the grid: what a trigger of a button does. Choosing "native" for all three triggers
/// of a button hands the key back to macOS.
struct RemoteButtonActionMenu: View {
    let button: RemoteButton
    let trigger: ButtonTrigger
    @EnvironmentObject private var settings: AppSettings
    @State private var recording = false
    private static let cellWidth: CGFloat = 128

    private var current: ButtonAction { settings.remoteButtonProfile.bindings(for: button).action(for: trigger) }
    private var summary: String {
        RemoteButtonMappingText.summary(of: current, appName: RemoteButtonMappingText.installedAppName)
    }

    var body: some View {
        Menu {
            choice(.native, L("remote_buttons.action.native"))
            Divider()
            Menu(L("remote_buttons.action.media")) {
                ForEach(SystemKey.allCases, id: \.self) { key in
                    choice(.system(key), L(RemoteButtonMappingText.systemKey(key)))
                }
            }
            choice(.showDesktop, L("remote_buttons.action.show_desktop"))
            choice(.appSwitcher, L("remote_buttons.action.app_switcher"))
            Divider()
            Button(L("remote_buttons.action.shortcut")) { recording = true }
            Button(L("remote_buttons.action.open_app")) { chooseApp() }
        } label: {
            Text(summary)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(current == .native ? .secondary : .primary)
                .frame(width: Self.cellWidth - 28, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(width: Self.cellWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(L(RemoteButtonMappingText.buttonKey(button))), \(L(RemoteButtonMappingText.triggerKey(trigger)))")
        .accessibilityValue(summary)
        .popover(isPresented: $recording, arrowEdge: .bottom) {
            ShortcutRecorderView(
                onCapture: { chord in
                    assign(.key(chord))
                    recording = false
                },
                onCancel: { recording = false }
            )
        }
    }

    private func choice(_ action: ButtonAction, _ title: String) -> some View {
        Button {
            assign(action)
        } label: {
            if action == current { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func assign(_ action: ButtonAction) {
        var profile = settings.remoteButtonProfile
        profile.set(action, for: trigger, of: button)
        settings.remoteButtonProfile = profile
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = L("remote_buttons.pick_app")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty else { return }
        assign(.openApp(bundleID: id))
    }
}
