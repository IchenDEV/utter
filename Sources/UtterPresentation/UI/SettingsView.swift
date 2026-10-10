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
        TabView(selection: $state.selectedSettingsID) {
            ForEach(sections, id: \.id) { section in
                section.view(context)
                    .tabItem { Label(L(section.label), systemImage: section.symbol) }
                    .tag(section.id)
            }
        }
        .frame(width: SettingsWindowLayout.width, height: SettingsWindowLayout.height)
        .background(SettingsSurface.page)
        .id(settings.uiLanguage)
    }
}
