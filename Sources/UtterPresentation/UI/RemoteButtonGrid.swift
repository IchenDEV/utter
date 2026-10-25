import SwiftUI
import UtterContracts
import UtterPresentationContracts

/// Eleven keys by three triggers. Plain on purpose: a label per row, one menu per cell.
struct RemoteButtonGrid: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(ButtonTrigger.allCases, id: \.self) { trigger in
                    Text(L(RemoteButtonMappingText.triggerKey(trigger)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(RemoteButton.allCases, id: \.self) { button in
                GridRow {
                    Text(L(RemoteButtonMappingText.buttonKey(button)))
                        .gridColumnAlignment(.leading)
                    ForEach(ButtonTrigger.allCases, id: \.self) { trigger in
                        RemoteButtonActionMenu(button: button, trigger: trigger)
                    }
                }
            }
        }
        HStack {
            Spacer()
            Button(L("remote_buttons.restore_defaults")) {
                var profile = settings.remoteButtonProfile
                profile.restoreDefaults()
                settings.remoteButtonProfile = profile
            }
            .disabled(settings.remoteButtonProfile.isEmpty)
        }
    }
}
