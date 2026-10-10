import AppKit
import SwiftUI
import UtterContracts
import UtterPresentationContracts

/// Localization keys for the remote-mic diagnostics rows. Pure so the mapping is
/// unit-testable without a view.
package enum RemoteMicSettingsText {
    package static func discoveryKey(_ source: RemoteMicDiscoverySource?) -> String {
        switch source {
        case .connectedVoiceService: return "remote_mic.discovery.connected_voice"
        case .connectedHID: return "remote_mic.discovery.connected_hid"
        case .scan: return "remote_mic.discovery.scan"
        case nil: return "remote_mic.discovery.none"
        }
    }

    package static func captureKey(_ source: RemoteMicCaptureSource?) -> String {
        switch source {
        case .remote: return "remote_mic.capture.remote"
        case .systemRemoteUnavailable: return "remote_mic.capture.system_unavailable"
        case .systemRemoteSilent: return "remote_mic.capture.system_silent"
        case nil: return "remote_mic.capture.none"
        }
    }

    package static func decoderKey(lowNibbleFirst: Bool) -> String {
        lowNibbleFirst ? "remote_mic.decoder.low" : "remote_mic.decoder.standard"
    }

    /// The Bluetooth privacy pane when access was refused, the general pane otherwise.
    package static func bluetoothSettingsURL(for state: RemoteMicBridgeState) -> URL {
        if state == .unauthorized {
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
        }
        return URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
    }
}

struct RemoteMicSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var platform: PlatformProjection

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.remoteMicEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.remote_mic"))
                        Text(L("settings.remote_mic_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!platform.hasRemoteProvider)
            } footer: {
                Text(L("remote_mic.page.usage"))
            }

            if settings.remoteMicEnabled {
                connectionSection
                audioSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsPageSurface()
    }

    private var connectionSection: some View {
        Section {
            LabeledContent(L("settings.remote_mic_status")) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(platform.remoteState.isReady ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(platform.remoteState.summary)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(L("remote_mic.page.model")) {
                Text(platform.remoteDiagnostics.modelNumber ?? L("remote_mic.page.not_reported"))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent(L("remote_mic.page.found_via")) {
                Text(L(RemoteMicSettingsText.discoveryKey(platform.remoteDiagnostics.discovery)))
                    .foregroundStyle(.secondary)
            }
            LabeledContent(L("remote_mic.page.decoding")) {
                Text(L(RemoteMicSettingsText.decoderKey(lowNibbleFirst: platform.remoteDiagnostics.lowNibbleFirst)))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(L("remote_mic.page.reconnect")) { platform.reconnectRemoteMic() }
                Button(L("remote_mic.page.open_bluetooth")) {
                    NSWorkspace.shared.open(RemoteMicSettingsText.bluetoothSettingsURL(for: platform.remoteState))
                }
            }
        } header: {
            Text(L("remote_mic.page.connection"))
        } footer: {
            Text(L("remote_mic.page.troubleshooting"))
        }
    }

    private var audioSection: some View {
        Section {
            HStack {
                Text(L("settings.remote_mic_gain"))
                Slider(value: $settings.remoteMicGainDB, in: 0...24, step: 1)
                Text("\(Int(settings.remoteMicGainDB)) dB")
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
            LabeledContent(L("remote_mic.page.last_recording")) {
                Text(L(RemoteMicSettingsText.captureKey(platform.remoteDiagnostics.lastCapture)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text(L("remote_mic.page.audio"))
        } footer: {
            Text(L("remote_mic.page.audio_help"))
        }
    }
}
