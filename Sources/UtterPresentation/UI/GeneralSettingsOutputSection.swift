import SwiftUI
import UtterContracts
import UtterPresentationContracts

struct GeneralSettingsOutputSection: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Section {
            Picker(L("settings.output_mode"), selection: $settings.outputMode) {
                ForEach(OutputMode.allCases, id: \.self) { Text($0.label) }
            }
            Toggle(isOn: $settings.allowClipboardPaste) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("settings.allow_clipboard_paste"))
                    Text(L("settings.allow_clipboard_paste_help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    }
}
