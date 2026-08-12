import SwiftUI
import AVFoundation
import Speech

struct AboutView: View {
    @State private var showPermissions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                appInfo
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                Divider()

                permissionsSection
                    .padding(20)
            }
        }
    }

    // MARK: - App Info

    private var appInfo: some View {
        VStack(spacing: 6) {
            appIcon

            Text(ProductBrand.displayName)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(L("about.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 20) {
                Link("GitHub", destination: URL(string: "https://github.com/IchenDEV/utter")!)
                Link(L("about.feedback"), destination: URL(string: "https://github.com/IchenDEV/utter/issues")!)
            }
            .font(.caption)
            .padding(.top, 8)
        }
    }

    private var appIcon: some View {
        AppIconView(size: 64)
    }

    // MARK: - Permissions

    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var speechGranted = false
    @State private var screenCaptureGranted = false

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("settings.permissions"), systemImage: "lock.shield")
                    .font(.headline)
                Spacer()
                Button {
                    checkAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                permRow(icon: "hand.raised.fill", name: L("perm.accessibility"),
                        hint: L("perm.accessibility_hint"), granted: accessibilityGranted, action: openAccessibility)
                Divider().padding(.horizontal, 12)
                permRow(icon: "mic.fill", name: L("perm.microphone"),
                        hint: L("perm.microphone_hint"), granted: microphoneGranted, action: requestMicrophone)
                Divider().padding(.horizontal, 12)
                permRow(icon: "waveform", name: L("perm.speech"),
                        hint: L("perm.speech_hint"), granted: speechGranted, action: requestSpeech)
                Divider().padding(.horizontal, 12)
                permRow(icon: "rectangle.dashed.badge.record", name: L("perm.screen"),
                        hint: L("perm.screen_hint"), granted: screenCaptureGranted, action: requestScreenCapture)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

            Text("© 2026 Utter")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
        .onAppear { checkAll() }
    }

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
