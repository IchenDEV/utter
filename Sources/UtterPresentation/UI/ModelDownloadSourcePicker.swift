import SwiftUI
import UtterContracts
import UtterPresentationContracts

@MainActor
struct ModelDownloadSourcePicker: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(L("model.source.title"), selection: $settings.modelDownloadSource) {
                ForEach(ModelDownloadSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.menu)
            .id(settings.uiLanguage)
            .accessibilityIdentifier("model.download-source")

            Text(L("model.source.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.modelDownloadSource == .hfMirror {
                Text(L("model.source.mirror_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
