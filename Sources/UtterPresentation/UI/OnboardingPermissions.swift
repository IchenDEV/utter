import AppKit
import SwiftUI
import AVFoundation
import Speech
import UtterContracts
import UtterPresentationContracts

extension OnboardingView {
    // MARK: - Permissions


    var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("onboarding.grant_permissions"))
                    .font(.system(size: 20, weight: .bold))
                Text(L("onboarding.permissions_body"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            VStack(spacing: 0) {
                onboardPermissionRow(
                    icon: "hand.raised.fill",
                    name: L("perm.accessibility"),
                    hint: L("perm.accessibility_hint"),
                    granted: axGranted,
                    required: true
                ) { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
                Divider().padding(.horizontal, 12)
                onboardPermissionRow(
                    icon: "mic.fill",
                    name: L("perm.microphone"),
                    hint: L("perm.microphone_hint"),
                    granted: micGranted,
                    required: true
                ) { AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in refreshPermissions() } } }
                Divider().padding(.horizontal, 12)
                onboardPermissionRow(
                    icon: "waveform",
                    name: L("perm.speech"),
                    hint: L("perm.speech_hint"),
                    granted: speechGranted,
                    required: false
                ) { SFSpeechRecognizer.requestAuthorization { _ in Task { @MainActor in refreshPermissions() } } }
                Divider().padding(.horizontal, 12)
                onboardPermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    name: L("perm.screen"),
                    hint: L("perm.screen_hint"),
                    granted: screenGranted,
                    required: false
                ) {
                    platform.requestScreenPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshPermissions() }
                }
            }
            .background(SettingsSurface.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsSurface.cardStroke, lineWidth: 0.5))

            HStack {
                Spacer()
                Button {
                    refreshPermissions()
                } label: {
                    Label(L("common.refresh"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear { refreshPermissions() }
    }

    func onboardPermissionRow(
        icon: String, name: String, hint: String,
        granted: Bool, required: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 26)
                .foregroundStyle(granted ? .green : (required ? .orange : .secondary))

            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            } else {
                Button(L("perm.grant"), action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func refreshPermissions() {
        axGranted = AXIsProcessTrusted()
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        Task { @MainActor in
            let granted = await platform.checkScreenPermission()
            screenGranted = granted
        }
    }

    func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

}
