import SwiftUI
import UtterContracts
import UtterPresentationContracts

/// Localization keys and severity for the voice-key remap row. Pure so the mapping is
/// unit-testable without a view.
package enum RemoteKeyRemapText {
    package static func stateKey(_ state: RemoteKeyRemapState) -> String {
        switch state {
        case .off: return "remote_key.state.off"
        case .noRemote: return "remote_key.state.no_remote"
        case .waitingForService: return "remote_key.state.waiting"
        case .active: return "remote_key.state.active"
        case .conflict: return "remote_key.state.conflict"
        case .failed: return "remote_key.state.failed"
        }
    }

    /// A longer explanation, only for the states the user can act on.
    package static func detailKey(_ state: RemoteKeyRemapState) -> String? {
        switch state {
        case .conflict: return "remote_key.detail.conflict"
        case .failed: return "remote_key.detail.failed"
        case .off, .noRemote, .waitingForService, .active: return nil
        }
    }

    package static func needsAttention(_ state: RemoteKeyRemapState) -> Bool {
        detailKey(state) != nil
    }
}

struct RemoteKeyRemapRow: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var platform: PlatformProjection

    var body: some View {
        Toggle(isOn: $settings.remoteKeyRemapEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("remote_key.title"))
                Text(L("remote_key.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!platform.hasRemoteProvider)

        if settings.remoteKeyRemapEnabled, platform.hasRemoteProvider {
            LabeledContent(L("remote_key.status")) {
                HStack(spacing: 6) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(L(RemoteKeyRemapText.stateKey(platform.remoteDiagnostics.keyRemap)))
                        .foregroundStyle(.secondary)
                }
            }
            if let detail = RemoteKeyRemapText.detailKey(platform.remoteDiagnostics.keyRemap) {
                Text(L(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dotColor: Color {
        let state = platform.remoteDiagnostics.keyRemap
        if state == .active { return .green }
        return RemoteKeyRemapText.needsAttention(state) ? .orange : .secondary
    }
}
