import SwiftUI
import UtterContracts
import UtterPresentationContracts

struct UpdateMenuRow: View {
    @ObservedObject var update: UpdateProjection

    var body: some View {
        if update.status.isAvailable {
            Button { update.checkForUpdates() } label: {
                Label(UpdatePresentation.menuTitle(update.status), systemImage: symbol)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(UpdatePresentation.isHighlighted(update.status) ? Color.accentColor : Color.secondary)
            .disabled(!UpdatePresentation.canCheck(update.status))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var symbol: String {
        UpdatePresentation.isHighlighted(update.status) ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath"
    }
}

struct AboutUpdatesSection: View {
    @ObservedObject var update: UpdateProjection
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if update.status.isAvailable { content }
    }

    private var content: some View {
        Section {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("update.section")).font(.system(size: 12, weight: .medium))
                    if let line = UpdatePresentation.statusLine(update.status) {
                        Text(line).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(L("update.check")) { update.checkForUpdates() }
                    .controlSize(.small)
                    .disabled(!UpdatePresentation.canCheck(update.status))
            }
            Toggle(L("update.automatic"), isOn: $settings.automaticUpdateChecks)
            Text(L("update.privacy"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
