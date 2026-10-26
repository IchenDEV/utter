import UtterPresentationContracts
import UtterContracts
import AppKit
import SwiftUI

enum SettingsWindowLayout {
    static let width: CGFloat = 760
    static let height: CGFloat = 680
    static let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]

    static var contentSize: NSSize {
        NSSize(width: width, height: height)
    }
}

enum SettingsWindowTitle {
    static func text(for language: UILanguage) -> String {
        Loc.string("settings.window_title", language: language)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var state: AppState
    let sections: [PresentationContribution]
    let context: PresentationContext

    var body: some View {
        let tabs = SettingsTabLayout.tabs(from: sections)
        TabView(selection: selection(in: tabs)) {
            ForEach(tabs, id: \.id) { tab in
                content(of: tab)
                    .tabItem { Label(L(tab.label), systemImage: tab.symbol) }
                    .tag(tab.id)
            }
        }
        .frame(width: SettingsWindowLayout.width, height: SettingsWindowLayout.height)
        .background(SettingsSurface.page)
        .id(settings.uiLanguage)
    }

    @ViewBuilder
    private func content(of tab: SettingsTab) -> some View {
        if tab.isGroup {
            SettingsGroupPage(members: tab.members, context: context)
        } else if let page = tab.members.first {
            page.view(context)
        }
    }

    private func selection(in tabs: [SettingsTab]) -> Binding<String> {
        Binding(
            get: { SettingsTabLayout.selection(state.selectedSettingsID, in: tabs) ?? state.selectedSettingsID },
            set: { state.selectedSettingsID = $0 }
        )
    }
}
