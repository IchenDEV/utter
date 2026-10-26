import AppKit
import SwiftUI
import UtterContracts
import UtterPresentationContracts

/// The master switch, the status and the permission step of the button mapping. The grid appears
/// below it only while the mapping is on.
struct RemoteButtonMappingRow: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var platform: PlatformProjection

    private var available: Bool { platform.hasRemoteProvider && settings.remoteKeyRemapEnabled }
    private var state: RemoteButtonMappingState { platform.remoteDiagnostics.buttonMapping }

    /// Shows what is in effect: with the voice key remap off the mapping is off too, but the choice is kept.
    private var effectiveSwitch: Binding<Bool> {
        Binding(
            get: { settings.remoteKeyRemapEnabled && settings.remoteButtonMappingEnabled },
            set: { settings.remoteButtonMappingEnabled = $0 }
        )
    }

    var body: some View {
        Toggle(isOn: effectiveSwitch) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("remote_buttons.title"))
                Text(L("remote_buttons.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!available)

        if platform.hasRemoteProvider, !settings.remoteKeyRemapEnabled {
            Text(L("remote_buttons.needs_remap"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if available, settings.remoteButtonMappingEnabled {
            LabeledContent(L("remote_buttons.status")) {
                HStack(spacing: 6) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(L(RemoteButtonMappingText.stateKey(state)))
                        .foregroundStyle(.secondary)
                }
            }
            if let detail = RemoteButtonMappingText.detailKey(state) {
                Text(L(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            permissionButton
        }
    }

    @ViewBuilder
    private var permissionButton: some View {
        switch RemoteButtonMappingText.permissionAction(state) {
        case .allow:
            Button(L("remote_buttons.allow")) { platform.requestButtonMappingPermission() }
        case .openSettings:
            Button(L("remote_buttons.open_settings")) {
                NSWorkspace.shared.open(RemoteButtonMappingText.inputMonitoringSettingsURL)
            }
        case nil:
            EmptyView()
        }
    }

    private var dotColor: Color {
        if state == .active { return .green }
        return RemoteButtonMappingText.needsAttention(state) ? .orange : .secondary
    }
}
