import SwiftUI

enum SettingsWindowLayout {
    static let width: CGFloat = 920
    static let height: CGFloat = 680
    static let minimumWidth: CGFloat = 760
    static let minimumHeight: CGFloat = 540
}

enum SettingsWindowTitle {
    static var current: String {
        text(for: AppSettings.shared.uiLanguage)
    }

    static func text(for language: UILanguage) -> String {
        Loc.string("settings.window_title", language: language)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?
    var onLoadLLM: (() -> Void)?
    var onUnloadLocalASR: (() -> Void)?

    var body: some View {
        TabView {
            if ProductEdition.current.capabilities.activityHistory {
                HistoryStatsView()
                    .tabItem { Label(L("tab.history"), systemImage: "chart.line.uptrend.xyaxis") }
            }
            GeneralSettingsView()
                .tabItem { Label(L("tab.general"), systemImage: "slider.horizontal.3") }
            if ProductEdition.current.capabilities.modelManagement {
                ModelManagementView(
                    onUnloadWhisper: onUnloadWhisper,
                    onUnloadLLM: onUnloadLLM,
                    onLoadLLM: onLoadLLM,
                    onUnloadLocalASR: onUnloadLocalASR
                )
                .tabItem { Label(L("tab.models"), systemImage: "cpu") }
            }
            DictionaryStyleView()
                .tabItem { Label(L("tab.industry_lexicon"), systemImage: "cross.case") }
            if ProductEdition.current.capabilities.developerIntegrations {
                IntegrationsSettingsView()
                    .tabItem { Label(L("settings.integrations"), systemImage: "point.3.connected.trianglepath.dotted") }
            }
            AboutView()
                .tabItem { Label(L("tab.about"), systemImage: "info.circle") }
        }
        .frame(
            minWidth: SettingsWindowLayout.minimumWidth,
            minHeight: SettingsWindowLayout.minimumHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .id(settings.uiLanguage)
    }
}
