import AppKit
import SwiftUI

/// Localization keys for the remote-mic diagnostics rows. Pure so the mapping is
/// unit-testable without a view.
enum RemoteMicSettingsText {
    static func discoveryKey(_ source: RemoteMicDiscoverySource?) -> String {
        switch source {
        case .connectedVoiceService: return "remote_mic.discovery.connected_voice"
        case .connectedHID: return "remote_mic.discovery.connected_hid"
        case .scan: return "remote_mic.discovery.scan"
        case nil: return "remote_mic.discovery.none"
        }
    }

    static func captureKey(_ source: RemoteMicCaptureSource?) -> String {
        switch source {
        case .remote: return "remote_mic.capture.remote"
        case .systemNoRemoteSession: return "remote_mic.capture.system_no_session"
        case .systemRemoteUnavailable: return "remote_mic.capture.system_unavailable"
        case nil: return "remote_mic.capture.none"
        }
    }

    static func decoderKey(lowNibbleFirst: Bool) -> String {
        lowNibbleFirst ? "remote_mic.decoder.low" : "remote_mic.decoder.standard"
    }

    /// The Bluetooth privacy pane when access was refused, the general pane otherwise.
    static func bluetoothSettingsURL(for state: RemoteMicBridgeState) -> URL {
        if state == .unauthorized {
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
        }
        return URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
    }
}

struct RemoteMicSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var bridge = XiaomiRemoteMicBridge.shared

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
                        .fill(bridge.state.isReady ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(bridge.state.summary)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(L("remote_mic.page.model")) {
                Text(bridge.diagnostics.modelNumber ?? L("remote_mic.page.not_reported"))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent(L("remote_mic.page.found_via")) {
                Text(L(RemoteMicSettingsText.discoveryKey(bridge.diagnostics.discovery)))
                    .foregroundStyle(.secondary)
            }
            LabeledContent(L("remote_mic.page.decoding")) {
                Text(L(RemoteMicSettingsText.decoderKey(lowNibbleFirst: bridge.diagnostics.lowNibbleFirst)))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(L("remote_mic.page.reconnect")) { bridge.reconnectNow() }
                Button(L("remote_mic.page.open_bluetooth")) {
                    NSWorkspace.shared.open(RemoteMicSettingsText.bluetoothSettingsURL(for: bridge.state))
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
                Text(L(RemoteMicSettingsText.captureKey(bridge.diagnostics.lastCapture)))
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
