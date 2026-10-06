import SwiftUI
import UtterMobile

@MainActor
struct MobileSettingsView: View {
    @ObservedObject var controller: MobileController
    @AppStorage("keyboard.haptics", store: keyboardPreferences()) private var haptics = true
    @AppStorage("keyboard.sounds", store: keyboardPreferences()) private var sounds = false
    @State private var confirmingClear = false
    var body: some View {
        Form {
            Section {
                Picker(L("ios.language"), selection: Binding(get: { controller.language }, set: { value in Task { await controller.changeLanguage(value) } })) {
                    Text(L("ios.language.zh")).tag("zh")
                    Text(L("ios.language.en")).tag("en")
                }.disabled(!controller.canChangeConfiguration).accessibilityIdentifier("voice.language")
                Picker(L("ios.settings.duration"), selection: Binding(get: { controller.recordingLimit }, set: { controller.recordingLimit = $0 })) {
                    ForEach([30, 60, 120], id: \.self) { Text(String(format: L("ios.settings.seconds"), $0)).tag($0) }
                }.disabled(!controller.canChangeConfiguration).accessibilityIdentifier("settings.duration")
                Picker(L("settings.audio_sensitivity"), selection: Binding(get: { controller.audioSensitivity }, set: { controller.audioSensitivity = $0 })) {
                    ForEach(["conservative", "standard", "sensitive"], id: \.self) { Text(L("settings.sensitivity.\($0)")).tag($0) }
                }.disabled(!controller.canChangeConfiguration)
                Picker(L("industry.lexicon.title"), selection: Binding(get: { controller.industryLexicon }, set: { controller.industryLexicon = $0 })) {
                    ForEach(["general", "medical", "legal", "finance", "technology"], id: \.self) { Text(L("industry.lexicon.\($0)")).tag($0) }
                }.disabled(!controller.canChangeConfiguration)
                NavigationLink(L("ios.dictionary")) { DictionaryView(controller: controller) }.accessibilityIdentifier("dictionary.open")
            } header: { mobileSectionHeader("ios.settings.recognition") }
            Section {
                Toggle(L("ios.settings.polish"), isOn: $controller.polishEnabled)
                    .disabled(!controller.polishAvailable).accessibilityIdentifier("settings.polish")
                LabeledContent(L("ios.settings.polish_model"), value: controller.polishModelName)
                    .accessibilityIdentifier("settings.polish.model")
            } footer: { mobileSectionFooter(controller.polishAvailable ? "ios.settings.polish_notice" : "ios.settings.polish_unavailable") }
            Section {
                Toggle(L("ios.settings.haptics"), isOn: $haptics).accessibilityIdentifier("settings.haptics")
                Toggle(L("ios.settings.sounds"), isOn: $sounds).accessibilityIdentifier("settings.sounds")
            } header: { mobileSectionHeader("ios.settings.feedback") } footer: { mobileSectionFooter("ios.settings.feedback_notice") }
            Section {
                Label(L("ios.settings.local_only"), systemImage: "iphone")
                Text(L("ios.settings.history_off"))
                Button(L("ios.settings.permissions"), action: openUtterSettings)
                Button(L("ios.action.clear_data"), role: .destructive) { confirmingClear = true }
                    .disabled(!controller.canChangeConfiguration).accessibilityIdentifier("voice.clear_data")
            } header: { mobileSectionHeader("ios.settings.privacy") }
            Section {
                LabeledContent(L("ios.settings.version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                Text(L("ios.settings.wake_notice"))
            } header: { mobileSectionHeader("ios.settings.about") }
        }.navigationTitle(L("ios.tab.settings")).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(L("ios.action.clear_data"), isPresented: $confirmingClear, titleVisibility: .visible) {
                Button(L("ios.action.clear_data"), role: .destructive) { Task { if await controller.clearLocalData() { await controller.prepareLibrary() } } }
                    .accessibilityIdentifier("voice.clear_confirm")
            } message: { Text(L("ios.settings.clear_notice")) }
    }
}
