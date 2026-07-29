import SwiftUI

enum SettingsWindowLayout {
    static let width: CGFloat = 760
    static let height: CGFloat = 540
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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?
    var onLoadLLM: (() -> Void)?
    var onUnloadLocalASR: (() -> Void)?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L("tab.general"), systemImage: "gear") }
            ModelManagementView(
                onUnloadWhisper: onUnloadWhisper,
                onUnloadLLM: onUnloadLLM,
                onLoadLLM: onLoadLLM,
                onUnloadLocalASR: onUnloadLocalASR
            )
                .tabItem { Label(L("tab.models"), systemImage: "cpu") }
            DictionaryStyleView()
                .tabItem { Label(L("tab.style"), systemImage: "text.book.closed") }
            HistoryStatsView()
                .tabItem { Label(L("tab.history"), systemImage: "clock.arrow.circlepath") }
            IntegrationsSettingsView()
                .tabItem { Label(L("settings.integrations"), systemImage: "point.3.connected.trianglepath.dotted") }
            aboutTab
                .tabItem { Label(L("tab.about"), systemImage: "info.circle") }
        }
        .frame(width: SettingsWindowLayout.width, height: SettingsWindowLayout.height)
        .id(settings.uiLanguage)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section(L("settings.activation")) {
                Picker(L("settings.hotkey"), selection: $settings.hotkeyType) {
                    ForEach(HotkeyType.allCases, id: \.self) { Text($0.rawValue) }
                }
                Picker(L("settings.mode"), selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { Text($0.label) }
                }
                if settings.activationMode == .doubleTap {
                    HStack {
                        Text(L("settings.tap_interval"))
                        Slider(value: $settings.tapInterval, in: 0.2...0.8, step: 0.05)
                        Text("\(settings.tapInterval, specifier: "%.2f")s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }

            Section(L("settings.output")) {
                Picker(L("settings.output_mode"), selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases, id: \.self) { Text($0.label) }
                }
                Picker(L("settings.recognition_language"), selection: $settings.inputLanguage) {
                    ForEach(InputLanguage.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle(isOn: $settings.enableInstantInsert) {
                    Text(L("settings.instant_insert"))
                }
                .help(L("settings.instant_insert_help"))
                .disabled(settings.outputMode != .processed)
            }

            Section(L("settings.translation")) {
                Picker(L("settings.translation_target"), selection: $settings.translationTargetLanguage) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }

                HStack {
                    Text(L("settings.translation_shortcut"))
                    Spacer()
                    shortcutKeycap(settings.hotkeyType.rawValue)
                    Text("+")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.translationHotkeyModifier) {
                        ForEach(HotkeyType.allCases, id: \.self) { key in
                            Text(key.rawValue)
                                .tag(key)
                                .disabled(key == settings.hotkeyType)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Text(L("settings.translation_shortcut_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.beta")) {
                Toggle(isOn: $settings.enableStreamingRecognitionBeta) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.streaming_beta"))
                        Text(L("settings.streaming_beta_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L("settings.audio")) {
                microphonePicker
                Toggle(isOn: $settings.useScreenContext) {
                    Text(L("settings.screen_context"))
                }
                .help(L("settings.screen_context_help"))
                Picker(L("settings.screen_context_mode"), selection: $settings.screenContextMode) {
                    ForEach(ScreenContextMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help(L("settings.screen_context_mode_help"))
                Toggle(isOn: $settings.playSounds) {
                    Text(L("settings.sound_cues"))
                }
            }

            Section(L("settings.memory")) {
                Toggle(isOn: $settings.enableMemory) {
                    Text(L("settings.enable_memory"))
                }
                Picker(L("settings.memory_window"), selection: $settings.memoryWindowMinutes) {
                    Text(String(format: L("settings.memory_minutes_fmt"), 5)).tag(5)
                    Text(String(format: L("settings.memory_minutes_fmt"), 15)).tag(15)
                    Text(String(format: L("settings.memory_minutes_fmt"), 30)).tag(30)
                    Text(String(format: L("settings.memory_minutes_fmt"), 60)).tag(60)
                }
            }

            Section(L("settings.interface")) {
                Picker(L("settings.ui_language"), selection: $settings.uiLanguage) {
                    ForEach(UILanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                HStack {
                    Picker(L("settings.app_icon"), selection: $settings.appIconAppearance) {
                        ForEach(AppIconAppearance.allCases, id: \.self) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    AppIconView(size: 28)
                }
                HStack {
                    Text(L("settings.menubar_icon"))
                    Spacer()
                    HStack(spacing: 12) {
                        ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                            Button {
                                settings.menuBarIcon = icon
                            } label: {
                                Image(systemName: icon.symbolName)
                                    .font(.system(size: 16))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        settings.menuBarIcon == icon
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                settings.menuBarIcon == icon
                                                    ? Color.accentColor
                                                    : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(icon.label)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - About (with Permissions)

    private var aboutTab: some View {
        AboutView()
    }

    private var microphonePicker: some View {
        let mics = AudioCaptureManager.availableMicrophones()
        return Picker(L("settings.microphone"), selection: $settings.microphoneID) {
            Text(L("settings.system_default")).tag(nil as String?)
            ForEach(mics, id: \.id) { mic in
                Text(mic.name).tag(mic.id as String?)
            }
        }
    }

    private func shortcutKeycap(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .rounded, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
