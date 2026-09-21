import SwiftUI
import AVFoundation
import Speech

struct PermissionsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var speechGranted = false
    @State private var screenCaptureGranted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("perm.intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    permissionRow(
                        icon: "hand.raised.fill",
                        name: L("perm.accessibility"),
                        hint: L("perm.accessibility_desc"),
                        granted: accessibilityGranted,
                        action: openAccessibility
                    )
                    Divider().padding(.horizontal, 12)
                    permissionRow(
                        icon: "mic.fill",
                        name: L("perm.microphone"),
                        hint: L("perm.microphone_desc"),
                        granted: microphoneGranted,
                        action: requestMicrophone
                    )
                    Divider().padding(.horizontal, 12)
                    permissionRow(
                        icon: "waveform",
                        name: L("perm.speech"),
                        hint: L("perm.speech_desc"),
                        granted: speechGranted,
                        action: requestSpeech
                    )
                    Divider().padding(.horizontal, 12)
                    permissionRow(
                        icon: "rectangle.dashed.badge.record",
                        name: L("perm.screen"),
                        hint: L("perm.screen_desc"),
                        granted: screenCaptureGranted,
                        action: requestScreenCapture
                    )
                }
                .background(SettingsSurface.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SettingsSurface.cardStroke, lineWidth: 0.5)
                )

                HStack {
                    Text(L("perm.help_text"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        checkAll()
                    } label: {
                        Label(L("common.refresh"), systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
            }
            .padding(20)
        }
        .onAppear { checkAll() }
    }

    // MARK: - Row

    private func permissionRow(
        icon: String, name: String, hint: String,
        granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 28)
                .foregroundStyle(granted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Label(L("perm.granted"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(L("perm.grant"), action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Check & Request

    private func checkAll() {
        accessibilityGranted = AXIsProcessTrusted()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        Task { @MainActor in
            let granted = await ScreenOCR.checkScreenCapturePermission()
            screenCaptureGranted = granted
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
