import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginRequiresApproval = false
    @State private var launchAtLoginErrorMessage = ""
    @State private var showsLaunchAtLoginError = false

    var body: some View {
        settingsForm
        .settingsPageSurface()
        .onAppear(perform: refreshLaunchAtLoginStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLoginStatus()
        }
        .alert(L("settings.launch_at_login_error_title"), isPresented: $showsLaunchAtLoginError) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(launchAtLoginErrorMessage)
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
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
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                SettingsSectionHeader(title: L("settings.activation"))
            } footer: {
                Text(L("settings.activation_help"))
            }

            Section {
                microphonePicker
                Picker(L("settings.recognition_language"), selection: $settings.inputLanguage) {
                    ForEach(InputLanguage.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle(isOn: $settings.enableStreamingRecognitionBeta) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.streaming_beta"))
                        Text(L("settings.streaming_beta_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SettingsSectionHeader(title: L("settings.audio"))
            }

            Section {
                Picker(L("settings.output_mode"), selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases, id: \.self) { Text($0.label) }
                }
                Toggle(isOn: $settings.enableInstantInsert) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.instant_insert"))
                        Text(L("settings.instant_insert_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(settings.outputMode != .processed)
            } header: {
                SettingsSectionHeader(title: L("settings.output"))
            }

            Section {
                Picker(L("settings.translation_target"), selection: $settings.translationTargetLanguage) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                HStack {
                    Text(L("settings.translation_shortcut"))
                    Spacer()
                    shortcutKeycap(settings.hotkeyType.rawValue)
                    Text("+").foregroundStyle(.secondary)
                    Picker("", selection: $settings.translationHotkeyModifier) {
                        ForEach(HotkeyType.allCases, id: \.self) { key in
                            Text(key.rawValue).tag(key).disabled(key == settings.hotkeyType)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } header: {
                SettingsSectionHeader(title: L("settings.translation"))
            } footer: {
                Text(L("settings.translation_shortcut_help"))
            }

            Section {
                Toggle(L("settings.screen_context"), isOn: $settings.useScreenContext)
                    .help(L("settings.screen_context_help"))
                Picker(L("settings.screen_context_mode"), selection: $settings.screenContextMode) {
                    ForEach(ScreenContextMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help(L("settings.screen_context_mode_help"))
                .disabled(!settings.useScreenContext)
                Toggle(L("settings.sound_cues"), isOn: $settings.playSounds)
            } header: {
                SettingsSectionHeader(title: L("settings.context_feedback"))
            }

            Section {
                Toggle(L("settings.enable_memory"), isOn: $settings.enableMemory)
                Picker(L("settings.memory_window"), selection: $settings.memoryWindowMinutes) {
                    ForEach([5, 15, 30, 60], id: \.self) { minutes in
                        Text(String(format: L("settings.memory_minutes_fmt"), minutes)).tag(minutes)
                    }
                }
                .disabled(!settings.enableMemory)
            } header: {
                SettingsSectionHeader(title: L("settings.memory"))
            } footer: {
                Text(L("settings.memory_help"))
            }

            Section {
                Toggle(isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: updateLaunchAtLogin
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.launch_at_login"))
                        Text(L("settings.launch_at_login_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if launchAtLoginRequiresApproval {
                    Label(L("settings.launch_at_login_requires_approval"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                SettingsSectionHeader(title: L("settings.startup"))
            }

            Section {
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
                menuBarIconPicker
            } header: {
                SettingsSectionHeader(title: L("settings.interface"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var microphonePicker: some View {
        Picker(L("settings.microphone"), selection: $settings.microphoneID) {
            Text(L("settings.system_default")).tag(nil as String?)
            ForEach(AudioCaptureManager.availableMicrophones(), id: \.id) { microphone in
                Text(microphone.name).tag(microphone.id as String?)
            }
        }
    }

    private var menuBarIconPicker: some View {
        HStack {
            Text(L("settings.menubar_icon"))
            Spacer()
            HStack(spacing: 8) {
                ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                    Button { settings.menuBarIcon = icon } label: {
                        Image(systemName: icon.symbolName)
                            .font(.system(size: 15))
                            .frame(width: 30, height: 26)
                            .background(
                                settings.menuBarIcon == icon ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(settings.menuBarIcon == icon ? Color.accentColor : .clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(icon.label)
                    .accessibilityLabel(icon.label)
                    .accessibilityAddTraits(settings.menuBarIcon == icon ? .isSelected : [])
                }
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

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
        } catch {
            Log.error("Failed to update launch at login: \(error.localizedDescription)")
            launchAtLoginErrorMessage = String(
                format: L("settings.launch_at_login_error"),
                error.localizedDescription
            )
            showsLaunchAtLoginError = true
        }
        refreshLaunchAtLoginStatus()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
        launchAtLoginRequiresApproval = LaunchAtLoginService.requiresApproval
    }
}

private struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
