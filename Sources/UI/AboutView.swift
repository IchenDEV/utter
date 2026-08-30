import SwiftUI
import AVFoundation
import Speech

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                permRow(icon: "hand.raised.fill", name: L("perm.accessibility"),
                        hint: L("perm.accessibility_hint"), granted: accessibilityGranted, action: openAccessibility)
                permRow(icon: "mic.fill", name: L("perm.microphone"),
                        hint: L("perm.microphone_hint"), granted: microphoneGranted, action: requestMicrophone)
                permRow(icon: "waveform", name: L("perm.speech"),
                        hint: L("perm.speech_hint"), granted: speechGranted, action: requestSpeech)
                permRow(icon: "rectangle.dashed.badge.record", name: L("perm.screen"),
                        hint: L("perm.screen_hint"), granted: screenCaptureGranted, action: requestScreenCapture)
            } header: {
                HStack {
                    Text(L("settings.permissions"))
                    Spacer()
                    Button {
                        checkAll()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("settings.permissions"))
                }
            }

            Section {
                appInfo
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsPageSurface()
        .onAppear { checkAll() }
    }

    // MARK: - App Info

    private var appInfo: some View {
        HStack(spacing: 14) {
            appIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(ProductBrand.displayName)
                    .font(.headline)
                Text(L("about.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("© 2026 Utter · \(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Link("GitHub", destination: URL(string: "https://github.com/IchenDEV/utter")!)
                Link(L("about.feedback"), destination: URL(string: "https://github.com/IchenDEV/utter/issues")!)
            }
            .font(.caption)
        }
    }

    private var appIcon: some View {
        AppIconView(size: 52)
    }

    private var version: String {
        "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")"
    }

    // MARK: - Permissions

    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var speechGranted = false
    @State private var screenCaptureGranted = false

    private func permRow(icon: String, name: String, hint: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 24)
                .foregroundStyle(granted ? .green : .orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(hint).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            } else {
                Button(L("perm.grant"), action: action)
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Permission actions

    private func checkAll() {
        accessibilityGranted = AXIsProcessTrusted()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        Task { @MainActor in
            screenCaptureGranted = await ScreenOCR.checkScreenCapturePermission()
        }
    }

    private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { checkAll() }
        }
    }

    private func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async { checkAll() }
        }
    }

    private func requestScreenCapture() {
        ScreenOCR.requestPermissionIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { checkAll() }
    }
}
