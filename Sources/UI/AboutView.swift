import SwiftUI
import AVFoundation
import Speech

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            SettingsPageHeader(
                kind: .about,
                title: ProductBrand.displayName,
                subtitle: ProductEdition.localizedName
            ) {
                SettingsPageBadge(title: version, symbol: "shippingbox")
            }
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    SettingsPanel { permissionsSection }
                    SettingsPanel { appInfo }
                }
                .padding(20)
            }
        }
        .settingsPageSurface()
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
                Text("© 2026 \(ProductBrand.displayName) · \(version) · \(L("edition.offline_badge"))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            if ProductEdition.current.capabilities.externalLinks {
                VStack(alignment: .trailing, spacing: 8) {
                    Link("GitHub", destination: URL(string: "https://github.com/IchenDEV/utter")!)
                    Link(L("about.feedback"), destination: URL(string: "https://github.com/IchenDEV/utter/issues")!)
                }
                .font(.caption)
            } else {
                Label(L("edition.network_disabled"), systemImage: "network.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                if ProductEdition.current.capabilities.modelManagement {
                    Divider().padding(.horizontal, 12)
                    permRow(icon: "waveform", name: L("perm.speech"),
                            hint: L("perm.speech_hint"), granted: speechGranted, action: requestSpeech)
                }
                Divider().padding(.horizontal, 12)
                permRow(icon: "rectangle.dashed.badge.record", name: L("perm.screen"),
                        hint: L("perm.screen_hint"), granted: screenCaptureGranted, action: requestScreenCapture)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

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
