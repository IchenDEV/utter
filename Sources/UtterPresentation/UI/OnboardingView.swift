import UtterPresentationContracts
import UtterContracts
import SwiftUI
import AVFoundation
import Speech

struct OnboardingView: View {
    @EnvironmentObject var platform: PlatformProjection
    let onComplete: () -> Void
    @State var step = 0
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var catalog: ModelCatalogProjection
    @State var skippedModelDownload = false
    @State var showModelDownloadConfirmation = false

    @State var axGranted = false
    @State var micGranted = false
    @State var speechGranted = false
    @State var screenGranted = false

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

    var welcomePage: some View {
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

    func featureBadge(icon: String, label: String) -> some View {
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

    var readyPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text(L("onboarding.all_set"))
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(L("onboarding.ready_body"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            HStack(spacing: 6) {
                Image(systemName: "fn")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text(L("onboarding.hold_hint"))
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Navigation

    var navigationBar: some View {
        HStack {
            if step > 0 {
                Button(L("common.back")) { step -= 1 }
                    .controlSize(.regular)
            }
            Spacer()
            stepIndicator
            Spacer()
            if step == 2 {
                Button(L("common.continue")) { step += 1 }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinueFromModelPrep)
            } else if step < 3 {
                Button(L("common.continue")) { step += 1 }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("onboarding.get_started")) { onComplete() }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
