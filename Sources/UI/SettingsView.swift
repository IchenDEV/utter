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
    var onBenchmarkLLM: ((String) async throws -> LLMEngine.BenchmarkResult)?
    var onUnloadLocalASR: (() -> Void)?

    var body: some View {
        TabView {
            HistoryStatsView()
                .tabItem { Label(L("tab.history"), systemImage: "chart.line.uptrend.xyaxis") }
            GeneralSettingsView()
                .tabItem { Label(L("tab.general"), systemImage: "slider.horizontal.3") }
            ModelManagementView(
                onUnloadWhisper: onUnloadWhisper,
                onUnloadLLM: onUnloadLLM,
                onLoadLLM: onLoadLLM,
                onBenchmarkLLM: onBenchmarkLLM,
                onUnloadLocalASR: onUnloadLocalASR
            )
            .tabItem { Label(L("tab.models"), systemImage: "cpu") }
            DictionaryStyleView()
                .tabItem { Label(L("tab.style"), systemImage: "text.book.closed") }
            IntegrationsSettingsView()
                .tabItem { Label(L("settings.integrations"), systemImage: "point.3.connected.trianglepath.dotted") }
            AboutView()
                .tabItem { Label(L("tab.about"), systemImage: "info.circle") }
        }
        .frame(width: SettingsWindowLayout.width, height: SettingsWindowLayout.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .id(settings.uiLanguage)
    }
}
