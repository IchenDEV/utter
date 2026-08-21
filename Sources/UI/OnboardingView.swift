import SwiftUI
import AVFoundation
import Speech

struct OnboardingView: View {
    let onComplete: () -> Void
    @State var step = 0
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var catalog = ModelCatalog.shared
    @State var skippedModelDownload = false
    @State var showModelDownloadConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcomePage
                case 1: permissionsPage
                case 2: modelPrepPage
                default: readyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: step)

            Divider()
            navigationBar
        }
        .frame(width: 480, height: 420)
        .alert(L("model.download_confirm_title"), isPresented: $showModelDownloadConfirmation) {
            Button(L("common.cancel"), role: .cancel) { }
            Button(L("common.download")) {
                Task { await catalog.downloadLLM(settings.llmModel) }
            }
        } message: {
            Text(onboardingDownloadConfirmationMessage)
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer()
            AppIconView(size: 72)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

            Text(L("onboarding.welcome"))
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(L("onboarding.welcome_body"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 24) {
                featureBadge(icon: "mic.fill", label: L("onboarding.voice_input"))
                featureBadge(icon: "brain", label: L("onboarding.smart_format"))
                featureBadge(icon: "lock.shield", label: L("onboarding.local"))
            }
            .padding(.top, 8)

            // Language selector on welcome page
            HStack(spacing: 8) {
                Text(L("onboarding.language"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.uiLanguage) {
                    ForEach(UILanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
            .padding(.top, 4)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    private func featureBadge(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    @State private var axGranted = false
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var screenGranted = false

    private var permissionsPage: some View {
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
                if ProductEdition.current.capabilities.modelManagement {
                    Divider().padding(.horizontal, 12)
                    onboardPermissionRow(
                        icon: "waveform",
                        name: L("perm.speech"),
                        hint: L("perm.speech_hint"),
                        granted: speechGranted,
                        required: false
                    ) { SFSpeechRecognizer.requestAuthorization { _ in Task { @MainActor in refreshPermissions() } } }
                }
                Divider().padding(.horizontal, 12)
                onboardPermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    name: L("perm.screen"),
                    hint: L("perm.screen_hint"),
                    granted: screenGranted,
                    required: false
                ) {
                    ScreenOCR.requestPermissionIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshPermissions() }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

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

    private func onboardPermissionRow(
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

    private func refreshPermissions() {
        axGranted = AXIsProcessTrusted()
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        Task { @MainActor in
            let granted = await ScreenOCR.checkScreenCapturePermission()
            screenGranted = granted
        }
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

}
